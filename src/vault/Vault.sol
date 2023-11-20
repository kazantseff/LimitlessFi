// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "lib/solmate/src/mixins/ERC4626.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {LimitlessMarket} from "../market/Market.sol";

error ProtocolInsolvent();

contract Vault is ERC4626, Ownable {
    using SafeTransferLib for ERC20;
    using SafeCast for uint;
    using SafeCast for int;
    using Math for uint;

    event UtilizationPercentageSet(uint256 indexed utilizationPercentage);
    event MarketSet(address indexed market);
    event BorrowingFeesDeposited(uint256 indexed amount);
    event BorrowingFeesClaimed(address indexed user, uint256 indexed amount);

    LimitlessMarket private market;
    uint256 public maxUtilizationPercentage;
    // The amount of underlying deposited
    uint256 public totalUnderlyingDeposited;
    uint256 public totalShares;
    uint256 public borrowingFees;

    struct userPosition {
        uint256 userLP;
        uint256 userFeesToClaim;
        uint256 lastAccruedTimestamp;
    }
    mapping(address => userPosition) public usersPosition;

    // Underlying will be USDC
    constructor(
        ERC20 _underlying
    ) ERC4626(_underlying, "LimitlessToken", "LMTLS") Ownable(msg.sender) {}

    /** @notice Returns the amount of underlying accounting for the protocol PNL */
    function totalAssets() public view override returns (uint256) {
        int256 balanceOfVault = totalUnderlyingDeposited.toInt256();
        // Pnl can be negative, but totalAssets should be at least 0
        int256 _totalAssets = balanceOfVault + market._calculateProtocolPnl();
        assert(_totalAssets > 0);
        return _totalAssets.toUint256();
    }

    /** @notice Function to deposit LP */
    function deposit(
        uint256 assets,
        address receiver
    ) public override returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
        totalUnderlyingDeposited += assets;
        usersPosition[receiver].userLP += shares;
        totalShares += shares;
    }

    /** @notice Function to redeem LP */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        assets = super.redeem(shares, receiver, owner);
        totalUnderlyingDeposited -= assets;
        usersPosition[owner].userLP -= shares;
        totalShares -= shares;

        // This check enusures that after withdrawal (totalOpenInterest < (depositedLiquidity * utilizationPercentage))
        require(
            market._ensureLiquidityReserves(),
            "Cannot withdraw liquidity reserved for positions"
        );
    }

    /** @notice Function to accept borrowing fees from a market */
    function depositBorrowingFees(uint256 amount) external {
        require(msg.sender == address(market), "Caller is not a market");
        borrowingFees += amount;
        ERC20(asset).safeTransferFrom(address(market), address(this), amount);

        emit BorrowingFeesDeposited(amount);
    }

    /** @notice Function that will distribute accruedFees to depositor to claim based on pro rata */
    // function distributeFees(address _user) external {
    //     usersPosition memory position = usersPosition[_user];
    //     // For the case of the first ever deposit, we should just set the timer to start accruing fees
    //     if (position.lastAccruedTimeStamp == 0) {
    //         position.lastAccruedTimeStamp = block.timestamp;
    //         return;
    //     }
    // }

    // function claimBorrowingFees() external {
    //     require(borrowingFees > 0, "Nothing to claim.");
    //     require(userLP[msg.sender] != 0, "Not LP depositor.");
    //     // To calcualte pro-rata we need to divide the totalAmount of fees by total LP shares
    //     // This way we get feesPerShare, and then multiply it by user amount of shares
    //     uint256 fees = borrowingFees.mulDiv(userLP[msg.sender], totalShares);
    //     borrowingFees -= fees;
    //     ERC20(asset).safeTransfer(msg.sender, fees);

    //     emit BorrowingFeesClaimed(msg.sender, fees);
    // }

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
