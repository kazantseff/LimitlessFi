// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** @notice Solmate SafeTransferLib, ERC4626, ERC20 */
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC4626} from "lib/solmate/src/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/** @notice OpenZeppelin Utils */
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/** @notice LimitlessMarket */
import {LimitlessMarket} from "../market/Market.sol";

contract LimitlessVault is ERC4626, Ownable {
    using SafeTransferLib for ERC20;
    using SafeCast for uint;
    using SafeCast for int;
    using Math for uint;

    LimitlessMarket private market;
    uint256 internal constant SCALE_FACTOR = 1e18;
    uint256 public maxUtilizationPercentage;
    uint256 public totalUnderlyingDeposited;
    uint256 public totalShares;
    uint256 public borrowingFees;

    struct userPosition {
        uint256 userShares;
        uint256 userFeesToClaim;
        uint256 lastAccruedTimestamp;
    }
    mapping(address => userPosition) public userToPosition;

    event UtilizationPercentageSet(uint256 indexed utilizationPercentage);
    event MarketSet(address indexed market);
    event BorrowingFeesDeposited(uint256 indexed amount);
    event BorrowingFeesAccrued(address indexed user, uint256 indexed amount);
    event BorrowingFeesClaimed(address indexed user, uint256 indexed amount);

    constructor(
        ERC20 _underlying,
        address _owner
    ) ERC4626(_underlying, "LimitlessToken", "LMTLS") Ownable(_owner) {}

    /** @notice Returns the amount of underlying accounting for traders PnL
     * @dev If traders' PnL is positive => deduct it from balance of vault
     * @dev If traders' PnL is negative => add it to balance of vault
     */
    function totalAssets() public view override returns (uint256) {
        int256 balanceOfVault = totalUnderlyingDeposited.toInt256();
        int256 _totalAssets = balanceOfVault - market._calculateTradersPnl();
        return _totalAssets.toUint256();
    }

    /** @notice Deposits underlying token into vault
     * @param assets Amount of underlying to deposit
     * @param receiver Receiver of shares
     * @return shares
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override returns (uint256 shares) {
        // Only accrueFees if user already has a position
        if (userToPosition[receiver].userShares > 0) {
            accrueFees(receiver);
        }

        shares = super.deposit(assets, receiver);
        totalUnderlyingDeposited += assets;
        userToPosition[receiver].userShares += shares;
        totalShares += shares;
    }

    /** @notice Function to redeem shares
     * @param shares Amount of shares to redeem
     * @param receiver Receiver of underying redeemed
     * @param owner Owner of shares
     * @return assets Underlying assets
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        accrueFees(owner);

        assets = super.redeem(shares, receiver, owner);
        totalUnderlyingDeposited -= assets;
        userToPosition[owner].userShares -= shares;
        totalShares -= shares;

        // This check ensures that after withdrawal totalOpenInterest is less than max utilization
        require(
            market._ensureLiquidityReserves(),
            "Cannot withdraw liquidity reserved for positions"
        );
    }

    /** @notice Accepts borrowing fees from market */
    function depositBorrowingFees(uint256 amount) external {
        require(msg.sender == address(market), "Caller is not a market");
        borrowingFees += amount;
        ERC20(asset).safeTransferFrom(address(market), address(this), amount);

        emit BorrowingFeesDeposited(amount);
    }

    /** @notice Accrues fees to a user
     * @notice Calculates the amount to accrue based on time spent in market and the pro rata share of the pool
     */
    // #TODO: Doee not work correctly, requires fix
    // @audit Maybe use some dividendPerShare variable
    function accrueFees(address user) public {
        userPosition memory position = userToPosition[user];
        uint256 deltaTime = block.timestamp - position.lastAccruedTimestamp;
        uint256 userShare = (position.userShares * SCALE_FACTOR) / totalShares;
        if (deltaTime > 0) {
            if (borrowingFees > 0) {
                uint256 accruedSinceUpdate = (deltaTime *
                    getDistributionSpeed() *
                    userShare) / SCALE_FACTOR;
                borrowingFees -= accruedSinceUpdate;
                position.userFeesToClaim += accruedSinceUpdate;

                emit BorrowingFeesAccrued(user, accruedSinceUpdate);
            }
            position.lastAccruedTimestamp = block.timestamp;
            userToPosition[user] = position;
        }
    }

    /** @notice Function to claim fees */
    function claimBorrowingFees() external {
        userPosition memory position = userToPosition[msg.sender];
        uint256 claimAmount = position.userFeesToClaim;
        require(claimAmount > 0, "Nothing to claim.");
        ERC20(asset).safeTransfer(msg.sender, claimAmount);
        position.userFeesToClaim = 0;
        userToPosition[msg.sender] = position;

        emit BorrowingFeesClaimed(msg.sender, claimAmount);
    }

    // #TODO: Should implement maxMint & maxDeposit

    /** @dev Utilization percentage is denominated in BPS */
    function setUtilizationPercentage(
        uint256 utilizationRate
    ) external onlyOwner {
        maxUtilizationPercentage = utilizationRate;

        emit UtilizationPercentageSet(utilizationRate);
    }

    function setMarket(address _market) external onlyOwner {
        market = LimitlessMarket(_market);

        emit MarketSet(_market);
    }

    function getDistributionSpeed() internal view returns (uint256) {
        // Distrubute tokens on an hourly basis
        return borrowingFees / 3600;
    }
}
