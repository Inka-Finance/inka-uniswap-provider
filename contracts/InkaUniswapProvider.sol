pragma solidity =0.6.12;

import "./utils/Ownable.sol";
import "./eth/interfaces/IUniswapV2Factory.sol";
import "./eth/libraries/UniswapV2Library.sol";
import './libraries/TransferHelper.sol';
import "./eth/interfaces/IWETH.sol";
import "./eth/interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Convert.sol";

contract InkaUniswapProvider is Ownable {
    using SafeMath for uint256;

    event InkaSwapOperation (
        uint256 amountOut, 
        uint256 fee
    );

    address public WETH;
    address public uniswapFactory;

    uint256 public providerFee = 3 * 10 ** 7;
    uint256 public constant FEE_DENOMINATOR = 10 ** 10;

    modifier ensure(uint deadline) {
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

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        require(IUniswapV2Factory(uniswapFactory).getPair(tokenA, tokenB) != address(0), "InkaUniswapProvider: PAIR_NOT_EXIST");
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(uniswapFactory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'InkaUniswapProvider: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'InkaUniswapProvider: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        return _addLiquiditySupportFee(tokenA, tokenB, amountA, amountB, to);
    }

    function _addLiquiditySupportFee(
        address tokenA, 
        address tokenB, 
        uint amountA, 
        uint amountB, 
        address to
    ) internal virtual returns(uint amountAOut, uint amountBOut, uint liquidity) {
        uint feeAmountA = amountA.mul(providerFee).div(FEE_DENOMINATOR);
        uint feeAmountB = amountB.mul(providerFee).div(FEE_DENOMINATOR);
        amountAOut = amountA.sub(feeAmountA);
        amountBOut = amountB.sub(feeAmountB);
        address pair = UniswapV2Library.pairFor(uniswapFactory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountAOut);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountBOut);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );

        return _addLiquidityETHSupportFee(token, amountToken, amountETH, amountTokenMin, amountETHMin, to);
    }

    function _addLiquidityETHSupportFee(
        address token,
        uint amountToken,
        uint amountETH,
        uint amountTokenMin,
        uint amountETHMin,
        address to
    ) internal virtual returns(uint amountOutToken, uint amountOutETH, uint liquidity) {
        require(IERC20(token).balanceOf(msg.sender) >= amountToken, 'InkaUniswapProvider: INSUFFICIENT_BALANCE');
        require(IERC20(token).allowance(msg.sender, address(this)) >= amountToken, 'InkaUniswapProvider: INSUFFICIENT_ALLOWANCE');
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amountToken);

        uint feeAmountToken = amountToken.mul(providerFee).div(FEE_DENOMINATOR);
        uint feeAmountETH = amountETH.mul(providerFee).div(FEE_DENOMINATOR);

        amountOutToken = amountToken.sub(feeAmountToken);
        amountOutETH = amountETH.sub(feeAmountETH);
        require(amountOutToken >= amountTokenMin, 'InkaUniswapProvider: INSUFFICIENT_OUTPUT_AMOUNT');
        require(amountOutETH >= amountETHMin, 'InkaUniswapProvider: INSUFFICIENT_OUTPUT_AMOUNT');
        address pair = UniswapV2Library.pairFor(uniswapFactory, token, WETH);
        TransferHelper.safeTransfer(token, pair, amountOutToken);
        IWETH(WETH).deposit{value: amountOutETH}();
        assert(IWETH(WETH).transfer(pair, amountOutETH));
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function swapTokensForETHSupportingFee(
        uint amountIn,
        uint swapAmountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        uint amountOut = _swapTokensForETHSupportingFee(amountIn, swapAmountOutMin, path);
        uint feeAmount = amountOut.mul(providerFee).div(FEE_DENOMINATOR);

        emit InkaSwapOperation(amountOut, feeAmount);

        IWETH(WETH).withdraw(amountOut);
        uint adjustedAmountOut = amountOut.sub(feeAmount);
        TransferHelper.safeTransferETH(to, adjustedAmountOut);
    }

    function _swapTokensForETHSupportingFee(
        uint amountIn,
        uint swapAmountOutMin,
        address[] calldata path
    ) internal virtual returns (uint) {
        require(path[path.length - 1] == WETH, 'InkaUniswapProvider: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(uniswapFactory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(WETH).balanceOf(address(this));
        _swap(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this)).sub(balanceBefore);
        require(amountOut >= swapAmountOutMin, 'InkaUniswapProvider: INSUFFICIENT_OUTPUT_AMOUNT');
        return amountOut;
    }

    function swapTokensForTokensSupportingFee(
        uint amountIn,
        uint swapAmountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        uint amountOut = _swapTokensForTokensSupportingFee(amountIn, swapAmountOutMin, path);
        uint feeAmount = amountOut.mul(providerFee).div(FEE_DENOMINATOR);

        emit InkaSwapOperation(amountOut, feeAmount);

        uint adjustedAmountOut = amountOut.sub(feeAmount);
        TransferHelper.safeTransfer(path[path.length - 1], to, adjustedAmountOut);
    }

    function _swapTokensForTokensSupportingFee(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path
    ) internal virtual returns (uint) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(uniswapFactory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(address(this));
        _swap(path, address(this));
        uint amountOut = IERC20(path[path.length - 1]).balanceOf(address(this)).sub(balanceBefore);
        require(amountOut >= amountOutMin, 'InkaUniswapProvider: INSUFFICIENT_OUTPUT_AMOUNT');
        return amountOut;
    }

    function swapETHForTokensSupportingFee(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual payable ensure(deadline) {
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
        _swap(path, address(this));
        uint amountOut = IERC20(path[path.length - 1]).balanceOf(address(this)).sub(balanceBefore);
        require(amountOut >= amountOutMin, 'InkaUniswapProvider: INSUFFICIENT_OUTPUT_AMOUNT');
        return amountOut;
    }

    function _swap(address[] memory path, address _to) internal virtual {
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