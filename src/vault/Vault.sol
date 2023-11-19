// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "lib/solmate/src/mixins/ERC4626.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {LimitlessMarket} from "../market/Market.sol";

error ProtocolInsolvent();

contract Vault is ERC4626, Ownable {
    using SafeTransferLib for ERC20;
    using SafeCast for uint;
    using SafeCast for int;

    event UtilizationPercentageSet(uint256 indexed utilizationPercentage);
    event MarketSet(address indexed market);
    event BorrowingFeesDeposited(uint256 indexed amount);

    LimitlessMarket private market;
    uint256 public maxUtilizationPercentage;
    // The amount of underlying deposited
    uint256 public totalUnderlyingDeposited;
    uint256 public borrowingFees;
    mapping(address user => uint256 amount) public userLP;

    // Underlying will be USDC
    constructor(
        ERC20 _underlying
    ) ERC4626(_underlying, "LimitlessToken", "LMTLS") Ownable(msg.sender) {}

    /** @notice Returns the amount of underlying accounting for the protocol PNL */
    function totalAssets() public view override returns (uint256) {
        int256 balanceOfVault = totalUnderlyingDeposited.toInt256();
        // Pnl can be negative, but totalAssets should be at least 0
        int256 _totalAssets = balanceOfVault - market._calculateProtocolPnl();
        if (_totalAssets < 0) revert ProtocolInsolvent();
        return _totalAssets.toUint256();
    }

    /** @notice Function to deposit LP */
    function deposit(
        uint256 assets,
        address receiver
    ) public override returns (uint256 shares) {
        totalUnderlyingDeposited += assets;
        shares = super.deposit(assets, receiver);
        userLP[receiver] += shares;
    }

    /** @notice Function to redeem LP */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        assets = super.redeem(shares, receiver, owner);
        totalUnderlyingDeposited -= assets;
        userLP[owner] -= shares;
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

    function claimBorrowingFees() external {
        require(borrowingFees > 0, "Nothing to claim.");
        require(userLP[msg.sender] != 0, "Not LP depositor.");
        // To calcualte pro-rata we need to divide the totalAmount of fees by total LP shares
        // And then multiply the result by user's LP
    }

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
