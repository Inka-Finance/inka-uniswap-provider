const InkaUniswapProvider = artifacts.require("InkaUniswapProvider");

const WETH_RINKEBY = "0xc778417E063141139Fce010982780140Aa0cD5Ab"
const RINKEBY_UNISWAP_FACTORY = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"

const WETH_KOVAN = "0xd0A1E359811322d97991E03f863a0C30C2cF029C";
const KOVAN_UNISWAP_FACTORY = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";

module.exports = function (deployer) {
  deployer.deploy(InkaUniswapProvider, WETH_KOVAN, KOVAN_UNISWAP_FACTORY);
};
