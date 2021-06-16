const InkaUniswapProvider = artifacts.require("InkaUniswapProvider");

const WETH = "0xc778417E063141139Fce010982780140Aa0cD5Ab"
const RINKEBY_UNISWAP_FACTORY = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"

module.exports = function (deployer) {
  deployer.deploy(InkaUniswapProvider, WETH, RINKEBY_UNISWAP_FACTORY);
};
