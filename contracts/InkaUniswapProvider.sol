pragma solidity =0.6.12;

import "./utils/Ownable.sol";
import "./eth/interfaces/IUniswapV2Factory.sol";
import "./eth/libraries/UniswapV2Library.sol";
import './libraries/TransferHelper.sol';
import "./eth/interfaces/IWETH.sol";
import "./eth/interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Convert.sol";

import { UniswapOracle } from  '@Keydonix/uniswap-oracle-contracts/source/UniswapOracle.sol';
import { IUniswapV2Pair } from "@Keydonix/uniswap-oracle-contracts/source/IUniswapV2Pair.sol"

contract InkaUniswapProvider is UniswapOracle {
    using SafeMath for uint256;

    event InkaSwapOperation (
        uint256 amountOut, 
        uint256 fee
    );

    address public WETH;
    address public uniswapFactory;

    uint256 public providerFee = 3 * 10 ** 7;
    uint256 public constant FEE_DENOMINATOR = 10 ** 10;

    modifier deadlineCheck(uint deadline) {
        require(deadline >= block.timestamp, 'InkaUniswapProvider: DEADLINE_EXPIRED');
        _;
    }

    constructor (
        address _weth,
        address _factory
    ) public {
        require(_weth != address(0), "InkaUniswapProvider: ZERO_WETH_ADDRESS");
        require(_factory != address(0), "InkaUniswapProvider: ZERO_FACTORY_ADDRESS");

        WETH = _weth;
        uniswapFactory = _factory;
    }

    function swapETHForTokensSupportingFee(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual payable deadlineCheck(deadline) {
        uint amountOut = _swapETHForTokensSupportingFee(amountOutMin, path, 0);
        uint feeAmount = amountOut.mul(providerFee).div(FEE_DENOMINATOR);

        emit InkaSwapOperation(amountOut, feeAmount);

        uint adjustedAmountOut = amountOut.sub(feeAmount);
        TransferHelper.safeTransfer(path[path.length - 1], to, adjustedAmountOut);
    }

    function _swapETHForTokensSupportingFee(
        uint amountOutMin,
        address[] calldata path,
        uint fee
    ) internal virtual returns (uint) {
        require(path[0] == WETH, 'InkaUniswapProvider: INVALID_PATH');
        uint amountIn = msg.value.sub(fee);
        require(amountIn > 0, 'InkaUniswapProvider: INSUFFICIENT_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(uniswapFactory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(address(this));
        _swapWithFeeTransferTokens(path, address(this));
        uint amountOut = IERC20(path[path.length - 1]).balanceOf(address(this)).sub(balanceBefore);
        require(amountOut >= amountOutMin, 'InkaUniswapProvider: INSUFFICIENT_OUTPUT_AMOUNT');
        return amountOut;
    }

    function _swapWithFeeTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            require(IUniswapV2Factory(uniswapFactory).getPair(input, output) != address(0), "InkaUniswapProvider: PAIR_NOT_EXIST");
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(uniswapFactory, input, output));
            uint amountInput;
            uint amountOutput;
            {
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(uniswapFactory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    receive() external payable { }

    function withdraw(address token) external {
        if (token == WETH) {
            uint256 wethBalance = IERC20(token).balanceOf(address(this));
            if (wethBalance > 0) {
                IWETH(WETH).withdraw(wethBalance);
            }
            TransferHelper.safeTransferETH(owner(), address(this).balance);
        } else {
            TransferHelper.safeTransfer(token, owner(), IERC20(token).balanceOf(address(this)));
        }
    }

    function setFee(uint _fee) external onlyOwner {
        providerFee = _fee;
    }

    function setUniswapFactory(address _factory) external onlyOwner {
        uniswapFactory = _factory;
    }
}