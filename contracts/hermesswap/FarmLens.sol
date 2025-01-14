// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";

import "../interfaces/IERC20.sol";
import "./interfaces/IHermesERC20.sol";
import "./interfaces/IHermesPair.sol";
import "./interfaces/IHermesFactory.sol";

import "../boringcrypto/BoringOwnable.sol";

interface IMasterChef {
    struct PoolInfo {
        IHermesERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. HERMES to distribute per block.
        uint256 lastRewardTimestamp; // Last block number that HERMES distribution occurs.
        uint256 accHermesPerShare; // Accumulated HERMES per share, times 1e12. See below.
    }

    function poolLength() external view returns (uint256);

    function poolInfo(uint256 pid) external view returns (IMasterChef.PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function hermesPerSec() external view returns (uint256);
}

contract FarmLens is BoringOwnable {
    using SafeMath for uint256;

    address public hermes; // 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    address public wone; // 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public woneUsdt; // 0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256
    address public woneUsdc; // 0x87Dee1cC9FFd464B79e058ba20387c1984aed86a
    address public woneDai; // 0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1
    IHermesFactory public hermesFactory; // IHermesFactory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);
    IMasterChef public chefv2; //0xd6a4F121CA35509aF06A0Be99093d08462f53052
    IMasterChef public chefv3; //0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00

    constructor(
        address hermes_,
        address wone_,
        address woneUsdt_,
        address woneUsdc_,
        address woneDai_,
        IHermesFactory hermesFactory_,
        IMasterChef chefv2_,
        IMasterChef chefv3_
    ) public {
        hermes = hermes_;
        wone = wone_;
        woneUsdt = woneUsdt_;
        woneUsdc = woneUsdc_;
        woneDai = woneDai_;
        hermesFactory = IHermesFactory(hermesFactory_);
        chefv2 = chefv2_;
        chefv3 = chefv3_;
    }

    /// @notice Returns price of one in usd.
    function getAvaxPrice() public view returns (uint256) {
        uint256 priceFromWoneUsdt = _getAvaxPrice(IHermesPair(woneUsdt)); // 18
        uint256 priceFromWoneUsdc = _getAvaxPrice(IHermesPair(woneUsdc)); // 18
        uint256 priceFromWoneDai = _getAvaxPrice(IHermesPair(woneDai)); // 18

        uint256 sumPrice = priceFromWoneUsdt.add(priceFromWoneUsdc).add(priceFromWoneDai); // 18
        uint256 onePrice = sumPrice / 3; // 18
        return onePrice; // 18
    }

    /// @notice Returns value of wone in units of stablecoins per wone.
    /// @param pair A wone-stablecoin pair.
    function _getAvaxPrice(IHermesPair pair) private view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        if (pair.token0() == wone) {
            reserve1 = reserve1.mul(_tokenDecimalsMultiplier(pair.token1())); // 18
            return (reserve1.mul(1e18)) / reserve0; // 18
        } else {
            reserve0 = reserve0.mul(_tokenDecimalsMultiplier(pair.token0())); // 18
            return (reserve0.mul(1e18)) / reserve1; // 18
        }
    }

    /// @notice Get the price of a token in Usd.
    /// @param tokenAddress Address of the token.
    function getPriceInUsd(address tokenAddress) public view returns (uint256) {
        return (getAvaxPrice().mul(getPriceInAvax(tokenAddress))) / 1e18; // 18
    }

    /// @notice Get the price of a token in Avax.
    /// @param tokenAddress Address of the token.
    /// @dev Need to be aware of decimals here, not always 18, it depends on the token.
    function getPriceInAvax(address tokenAddress) public view returns (uint256) {
        if (tokenAddress == wone) {
            return 1e18;
        }

        IHermesPair pair = IHermesPair(hermesFactory.getPair(tokenAddress, wone));

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        if (token0Address == wone) {
            reserve1 = reserve1.mul(_tokenDecimalsMultiplier(token1Address)); // 18
            return (reserve0.mul(1e18)) / reserve1; // 18
        } else {
            reserve0 = reserve0.mul(_tokenDecimalsMultiplier(token0Address)); // 18
            return (reserve1.mul(1e18)) / reserve0; // 18
        }
    }

    /// @notice Calculates the multiplier needed to scale a token's numerical field to 18 decimals.
    /// @param tokenAddress Address of the token.
    function _tokenDecimalsMultiplier(address tokenAddress) private pure returns (uint256) {
        uint256 decimalsNeeded = 18 - IHermesERC20(tokenAddress).decimals();
        return 1 * (10**decimalsNeeded);
    }

    /// @notice Calculates the reserve of a pair in usd.
    /// @param pair Pair for which the reserve will be calculated.
    function getReserveUsd(IHermesPair pair) public view returns (uint256) {
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        reserve0 = reserve0.mul(_tokenDecimalsMultiplier(token0Address)); // 18
        reserve1 = reserve1.mul(_tokenDecimalsMultiplier(token1Address)); // 18

        uint256 token0PriceInAvax = getPriceInAvax(token0Address); // 18
        uint256 token1PriceInAvax = getPriceInAvax(token1Address); // 18
        uint256 reserve0Avax = reserve0.mul(token0PriceInAvax); // 36;
        uint256 reserve1Avax = reserve1.mul(token1PriceInAvax); // 36;
        uint256 reserveAvax = (reserve0Avax.add(reserve1Avax)) / 1e18; // 18
        uint256 reserveUsd = (reserveAvax.mul(getAvaxPrice())) / 1e18; // 18

        return reserveUsd; // 18
    }

    struct FarmPair {
        uint256 id;
        uint256 allocPoint;
        address lpAddress;
        address token0Address;
        address token1Address;
        string token0Symbol;
        string token1Symbol;
        uint256 reserveUsd;
        uint256 totalSupplyScaled;
        address chefAddress;
        uint256 chefBalanceScaled;
        uint256 chefTotalAlloc;
        uint256 chefHermesPerSec;
    }

    /// @notice Gets the farm pair data for a given MasterChef.
    /// @param chefAddress The address of the MasterChef.
    /// @param whitelistedPids Array of all ids of pools that are whitelisted and valid to have their farm data returned.
    function getFarmPairs(address chefAddress, uint256[] calldata whitelistedPids)
        public
        view
        returns (FarmPair[] memory)
    {
        IMasterChef chef = IMasterChef(chefAddress);

        uint256 whitelistLength = whitelistedPids.length;
        FarmPair[] memory farmPairs = new FarmPair[](whitelistLength);

        for (uint256 i = 0; i < whitelistLength; i++) {
            IMasterChef.PoolInfo memory pool = chef.poolInfo(whitelistedPids[i]);
            IHermesPair lpToken = IHermesPair(address(pool.lpToken));

            //get pool information
            farmPairs[i].id = whitelistedPids[i];
            farmPairs[i].allocPoint = pool.allocPoint;

            // get pair information
            address lpAddress = address(lpToken);
            address token0Address = lpToken.token0();
            address token1Address = lpToken.token1();
            farmPairs[i].lpAddress = lpAddress;
            farmPairs[i].token0Address = token0Address;
            farmPairs[i].token1Address = token1Address;
            farmPairs[i].token0Symbol = IHermesERC20(token0Address).symbol();
            farmPairs[i].token1Symbol = IHermesERC20(token1Address).symbol();

            // calculate reserveUsd of lp
            farmPairs[i].reserveUsd = getReserveUsd(lpToken); // 18

            // calculate total supply of lp
            farmPairs[i].totalSupplyScaled = lpToken.totalSupply().mul(_tokenDecimalsMultiplier(lpAddress));

            // get masterChef data
            uint256 balance = lpToken.balanceOf(chefAddress);
            farmPairs[i].chefBalanceScaled = balance.mul(_tokenDecimalsMultiplier(lpAddress));
            farmPairs[i].chefAddress = chefAddress;
            farmPairs[i].chefTotalAlloc = chef.totalAllocPoint();
            farmPairs[i].chefHermesPerSec = chef.hermesPerSec();
        }

        return farmPairs;
    }

    struct AllFarmData {
        uint256 onePriceUsd;
        uint256 hermesPriceUsd;
        uint256 totalAllocChefV2;
        uint256 totalAllocChefV3;
        uint256 hermesPerSecChefV2;
        uint256 hermesPerSecChefV3;
        FarmPair[] farmPairsV2;
        FarmPair[] farmPairsV3;
    }

    /// @notice Get all data needed for useFarms hook.
    /// @param whitelistedPidsV2 Array of all ids of pools that are whitelisted in chefV2.
    /// @param whitelistedPidsV3 Array of all ids of pools that are whitelisted in chefV3.
    function getAllFarmData(uint256[] calldata whitelistedPidsV2, uint256[] calldata whitelistedPidsV3)
        public
        view
        returns (AllFarmData memory)
    {
        AllFarmData memory allFarmData;

        allFarmData.onePriceUsd = getAvaxPrice();
        allFarmData.hermesPriceUsd = getPriceInUsd(hermes);

        allFarmData.totalAllocChefV2 = IMasterChef(chefv2).totalAllocPoint();
        allFarmData.hermesPerSecChefV2 = IMasterChef(chefv2).hermesPerSec();

        allFarmData.totalAllocChefV3 = IMasterChef(chefv3).totalAllocPoint();
        allFarmData.hermesPerSecChefV3 = IMasterChef(chefv3).hermesPerSec();

        allFarmData.farmPairsV2 = getFarmPairs(address(chefv2), whitelistedPidsV2);
        allFarmData.farmPairsV3 = getFarmPairs(address(chefv3), whitelistedPidsV3);

        return allFarmData;
    }
}
