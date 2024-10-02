// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    TokenConfig,
    TokenType,
    LiquidityManagement,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { PoolHelpers, CustomPoolConfig, InitializationConfig } from "./PoolHelpers.sol";
import { ScaffoldHelpers, console } from "./ScaffoldHelpers.sol";
import { ConstantSumFactory } from "../contracts/factories/ConstantSumFactory.sol";
import { StakedGovernanceHook } from "../contracts/hooks/StakedGovernanceHook.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";

contract DeployConstantSumPoolWithStakedGovernanceHook is PoolHelpers, ScaffoldHelpers {
    function deployConstantSumPoolWithStakedGovernanceHook(address token1, address token2) internal {
        // change this manually, because msg.sender does not work when broadcasting :(
        address publicKey = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        // Start creating the transactions
        uint256 deployerPrivateKey = getDeployerPrivateKey();
        vm.startBroadcast(deployerPrivateKey);

        // Deploy a factory
        ConstantSumFactory factory = new ConstantSumFactory(vault, 365 days); // pauseWindowDuration
        console.log("Constant Sum Factory deployed at: %s", address(factory));

        // Deploy a mock ERC20 token to use as the governance token
        MockERC20 governanceToken = new MockERC20("Governance Token", "GOV");
        console.log("Governance Token deployed at: %s", address(governanceToken));

        // Set the pool's deployment, registration, and initialization config
        CustomPoolConfig memory poolConfig = getStakedGovernancePoolConfig(token1, token2);
        InitializationConfig memory initConfig = getStakedGovernancePoolInitConfig(token1, token2);

        // Deploy the StakedGovernanceHook
        StakedGovernanceHook stakedGovernanceHook = new StakedGovernanceHook(
            vault,
            IGovernanceToken(address(governanceToken)),
            IERC20(token2), // Assuming token2 is the stable token
            1e16 // 1% initial incentive fee
        );
        console.log("StakedGovernanceHook deployed at address: %s", address(stakedGovernanceHook));

        // Deploy a pool and register it with the vault
        address pool = factory.create(
            poolConfig.name,
            poolConfig.symbol,
            poolConfig.salt,
            poolConfig.tokenConfigs,
            poolConfig.swapFeePercentage,
            poolConfig.protocolFeeExempt,
            poolConfig.roleAccounts,
            address(stakedGovernanceHook),
            poolConfig.liquidityManagement
        );
        console.log("SumPoolWithStakedGovernanceHook deployed at: %s", pool);

        // Approve the router to spend tokens for pool initialization
        approveRouterWithPermit2(initConfig.tokens);

        // Seed the pool with initial liquidity
        router.initialize(
            pool,
            initConfig.tokens,
            initConfig.exactAmountsIn,
            initConfig.minBptAmountOut,
            initConfig.wethIsEth,
            initConfig.userData
        );
        console.log("SumPoolWithStakedGovernanceHook initialized successfully!");

        // Grant minter role to the StakedGovernanceHook
        governanceToken.grantRole(governanceToken.MINTER_ROLE(), address(stakedGovernanceHook));
        console.log("Minter role granted to StakedGovernanceHook");

        vm.stopBroadcast();
    }

    function getStakedGovernancePoolConfig(address token1, address token2) internal view returns (CustomPoolConfig memory config) {
        string memory name = "Constant Sum Pool With Staked Governance";
        string memory symbol = "CSP-SG";
        bytes32 salt = keccak256(abi.encode(block.number));
        uint256 swapFeePercentage = 0.01e18; // 1%
        bool protocolFeeExempt = true;

        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        tokenConfigs[0] = TokenConfig({
            token: IERC20(token1),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokenConfigs[1] = TokenConfig({
            token: IERC20(token2),
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: address(0),
            swapFeeManager: address(0),
            poolCreator: address(0)
        });
        LiquidityManagement memory liquidityManagement = LiquidityManagement({
            disableUnbalancedLiquidity: false,
            enableAddLiquidityCustom: false,
            enableRemoveLiquidityCustom: false,
            enableDonation: true
        });

        config = CustomPoolConfig({
            name: name,
            symbol: symbol,
            salt: salt,
            tokenConfigs: sortTokenConfig(tokenConfigs),
            swapFeePercentage: swapFeePercentage,
            protocolFeeExempt: protocolFeeExempt,
            roleAccounts: roleAccounts,
            poolHooksContract: address(0), // We'll set this to the StakedGovernanceHook address later
            liquidityManagement: liquidityManagement
        });
    }

    function getStakedGovernancePoolInitConfig(address token1, address token2) internal pure returns (InitializationConfig memory config) {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(token1);
        tokens[1] = IERC20(token2);
        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = 50e18;
        exactAmountsIn[1] = 50e18;
        uint256 minBptAmountOut = 99e18;
        bool wethIsEth = false;
        bytes memory userData = bytes("");

        config = InitializationConfig({
            tokens: InputHelpers.sortTokens(tokens),
            exactAmountsIn: exactAmountsIn,
            minBptAmountOut: minBptAmountOut,
            wethIsEth: wethIsEth,
            userData: userData
        });
    }
}
