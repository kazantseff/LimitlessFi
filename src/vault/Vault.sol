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

    struct userPosition {
        uint256 userShares;
        uint256 userFeesToClaim;
        uint256 lastAccruedTimestamp;
    }
    mapping(address => userPosition) public userToPosition;

    event UtilizationPercentageSet(uint256 indexed utilizationPercentage);
    event MarketSet(address indexed market);
    event DepositedFromMarket(uint256 indexed amount);
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

    /** @notice Accepts profit and fees from market */
    function depositProfitOrFees(uint256 amount) external {
        require(msg.sender == address(market), "Caller is not a market");
        totalUnderlyingDeposited += amount;
        asset.safeTransferFrom(address(market), address(this), amount);

        emit DepositedFromMarket(amount);
    }

    /** @notice Withdraw additional liquidity to market */
    function withdrawToMarket(uint256 amount) external {
        require(msg.sender == address(market), "Caller is not a market");
        totalUnderlyingDeposited -= amount;
        asset.safeTransfer(address(market), amount);
    }

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
}
