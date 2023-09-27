// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ERC20 }  from "@oz/token/ERC20/ERC20.sol";
import { IERC20 } from "@oz/token/ERC20/IERC20.sol";
import { Test }   from "@std/Test.sol";

import { AjnaToken }       from "../../src/token/AjnaToken.sol";
import { BurnWrappedAjna } from "../../src/token/BurnWrapper.sol";

import { SigUtils } from "../utils/SigUtils.sol";

contract BurnWrappedTokenTest is Test {

    /*************/
    /*** Setup ***/
    /*************/

    AjnaToken       internal _token;
    BurnWrappedAjna internal _wrappedToken;
    SigUtils        internal _sigUtils;

    address internal _ajnaAddress   = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079; // mainnet ajna token address
    address internal _tokenDeployer = 0x666cf594fB18622e1ddB91468309a7E194ccb799; // mainnet token deployer
    address internal _tokenHolder   = makeAddr("_tokenHolder");
    uint256 _initialAjnaTokenSupply = 1_000_000_000 * 1e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    function setUp() external {
        // create mainnet fork
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        // set fork block to block before token distribution
        vm.rollFork(16527772);

        // reference mainnet deployment
        _token = AjnaToken(_ajnaAddress);
        _wrappedToken = new BurnWrappedAjna(IERC20(address(_token)));
        
        _sigUtils = new SigUtils(_wrappedToken.DOMAIN_SEPARATOR());
    }

   function approveAndWrapTokens(address account_, uint256 amount_) internal {
        changePrank(account_);
        _token.approve(address(_wrappedToken), amount_);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(account_), address(0), amount_);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(account_), amount_);
        (bool wrapSuccess) = _wrappedToken.depositFor(account_, amount_);

        assertTrue(wrapSuccess);
    }

    /*************/
    /*** Tests ***/
    /*************/

    function testBaseInvariantMetadata() external {
        assertEq(_token.name(),     "AjnaToken");
        assertEq(_token.symbol(),   "AJNA");
        assertEq(_token.decimals(), 18);
    }

    function testWrappedInvariantMetadata() external {
        assertEq(_wrappedToken.name(),     "Burn Wrapped AJNA");
        assertEq(_wrappedToken.symbol(),   "bwAJNA");
        assertEq(_wrappedToken.decimals(), 18);
    }

    function testWrap() external {
        uint256 tokensToWrap = 50 * 1e18;

        // check initial token balances
        assertEq(_token.balanceOf(_tokenHolder), 0);
        assertEq(_wrappedToken.balanceOf(_tokenHolder), 0);
        assertEq(_token.balanceOf(address(_tokenDeployer)), _initialAjnaTokenSupply);
        assertEq(_wrappedToken.balanceOf(address(_tokenDeployer)), 0);

        // check initial token supply
        assertEq(_token.totalSupply(),        1_000_000_000 * 10 ** _token.decimals());
        assertEq(_token.totalSupply(),        _initialAjnaTokenSupply);
        assertEq(_wrappedToken.totalSupply(), 0);

        // transfer some tokens to the test address
        vm.startPrank(_tokenDeployer);
        _token.approve(address(_tokenDeployer), tokensToWrap);
        _token.transferFrom(_tokenDeployer, _tokenHolder, tokensToWrap);

        // check token balances after transfer
        assertEq(_token.balanceOf(_tokenHolder), tokensToWrap);
        assertEq(_wrappedToken.balanceOf(_tokenHolder), 0);
        assertEq(_token.balanceOf(address(_tokenDeployer)), _initialAjnaTokenSupply - tokensToWrap);
        assertEq(_wrappedToken.balanceOf(address(_tokenDeployer)), 0);

        // wrap tokens
        approveAndWrapTokens(_tokenHolder, tokensToWrap);

        // check token balances after wrapping
        assertEq(_token.balanceOf(_tokenHolder), 0);
        assertEq(_wrappedToken.balanceOf(_tokenHolder), tokensToWrap);
        assertEq(_token.balanceOf(address(_tokenDeployer)), _initialAjnaTokenSupply - tokensToWrap);
        assertEq(_wrappedToken.balanceOf(address(_tokenDeployer)), 0);

        // check token supply has decreased after wrapping by the wrapped amount
        assertEq(_token.totalSupply(),        _initialAjnaTokenSupply - tokensToWrap);
        assertEq(_wrappedToken.totalSupply(), tokensToWrap);
    }

    function testOnlyWrapAjna() external {
        ERC20 _invalidToken = new ERC20("Invalid Token", "INV");

        vm.expectRevert(BurnWrappedAjna.InvalidWrappedToken.selector);
        new BurnWrappedAjna(IERC20(address(_invalidToken)));
    }

    function testCantUnwrap() external {
        uint256 tokensToWrap = 50 * 1e18;

        // transfer some tokens to the test address
        vm.startPrank(_tokenDeployer);
        _token.approve(address(_tokenDeployer), tokensToWrap);
        _token.transferFrom(_tokenDeployer, _tokenHolder, tokensToWrap);

        // wrap tokens
        approveAndWrapTokens(_tokenHolder, tokensToWrap);

        // try to unwrap tokens
        vm.expectRevert(BurnWrappedAjna.UnwrapNotAllowed.selector);
        _wrappedToken.withdrawTo(_tokenHolder, 25 * 1e18);
    }

    function testApproveAndTransfer() external {
        uint256 tokensToTransfer = 500 * 1e18;
        address tokenReceiver = makeAddr("tokenReceiver");

        // transfer some tokens to the test address
        vm.startPrank(_tokenDeployer);
        _token.approve(address(_tokenDeployer), tokensToTransfer);
        _token.transferFrom(_tokenDeployer, _tokenHolder, tokensToTransfer);

        // wrap tokens
        approveAndWrapTokens(_tokenHolder, tokensToTransfer);

        // approve some tokens to the receiver address
        vm.startPrank(_tokenHolder);
        _wrappedToken.approve(tokenReceiver, tokensToTransfer);

        // check token allowance
        assertEq(_wrappedToken.allowance(_tokenHolder, tokenReceiver), tokensToTransfer);

        // transfer tokens
        changePrank(tokenReceiver);
        _wrappedToken.transferFrom(_tokenHolder, tokenReceiver, tokensToTransfer);

        // ensure tokens are transferred
        assertEq(_wrappedToken.balanceOf(tokenReceiver), tokensToTransfer);
    }

    function testIncreaseAndDecreaseAllowance() external {
        uint256 tokensToTransfer = 500 * 1e18;
        address tokenReceiver = makeAddr("tokenReceiver");

        // transfer some tokens to the test address
        vm.startPrank(_tokenDeployer);
        _token.approve(address(_tokenDeployer), tokensToTransfer);
        _token.transferFrom(_tokenDeployer, _tokenHolder, tokensToTransfer);

        // wrap tokens
        approveAndWrapTokens(_tokenHolder, tokensToTransfer);

        // approve some tokens to the test address
        vm.startPrank(_tokenHolder);
        _wrappedToken.approve(tokenReceiver, tokensToTransfer);

        // increase token allowance to 1000 tokens
        _wrappedToken.increaseAllowance(tokenReceiver, 500 * 1e18);

        // check allowance is increased
        assertEq(_wrappedToken.allowance(_tokenHolder, tokenReceiver), 1000 * 1e18);

        // decrease token allowance to 200 tokens
        _wrappedToken.decreaseAllowance(tokenReceiver, 800 * 1e18);

        // check allowance is decreased
        assertEq(_wrappedToken.allowance(_tokenHolder, tokenReceiver), 200 * 1e18);
    }

    function testDomainSeparatorAndUnderlyingToken() external {
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Burn Wrapped AJNA")),
                keccak256(bytes("1")),
                block.chainid,
                address(_wrappedToken)
            )
        );

        assertEq(_wrappedToken.DOMAIN_SEPARATOR(), expectedDomainSeparator);

        assertEq(address(_wrappedToken.underlying()), address(_token));
    }

    function testTransferWithPermit() external {
        uint256 tokensToTransfer = 500 * 1e18;

        // define owner and spender addresses
        (address owner, uint256 ownerPrivateKey) = makeAddrAndKey("owner");
        address spender                          = makeAddr("spender");
        address newOwner                         = makeAddr("newOwner");

        // set owner balance
        deal(address(_wrappedToken), owner, tokensToTransfer);

        // check owner and spender balances
        assertEq(_wrappedToken.balanceOf(owner),    tokensToTransfer);
        assertEq(_wrappedToken.balanceOf(spender),  0);
        assertEq(_wrappedToken.balanceOf(newOwner), 0);

        // TEST transfer with ERC20 permit
        vm.startPrank(owner);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: tokensToTransfer,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = _sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        _wrappedToken.permit(owner, spender, tokensToTransfer, permit.deadline, v, r, s);

        // check nonces is increased
        assertEq(_wrappedToken.nonces(owner), 1);

        changePrank(spender);
        _wrappedToken.transferFrom(owner, newOwner, tokensToTransfer);

        // check owner and spender balances after transfer
        assertEq(_wrappedToken.balanceOf(owner),    0);
        assertEq(_wrappedToken.balanceOf(spender),  0);
        assertEq(_wrappedToken.balanceOf(newOwner), tokensToTransfer);
        assertEq(_wrappedToken.allowance(owner, spender), 0);
    }

    function testBurn() external {
        uint256 tokensToBurn = 500 * 1e18;

        // transfer some tokens to the test address
        vm.startPrank(_tokenDeployer);
        _token.approve(address(_tokenDeployer), tokensToBurn);
        _token.transferFrom(_tokenDeployer, _tokenHolder, tokensToBurn);

        // wrap tokens
        approveAndWrapTokens(_tokenHolder, tokensToBurn);

        uint256 totalTokenSupply = _wrappedToken.totalSupply();

        uint256 snapshot = vm.snapshot();

        // burn tokens
        _wrappedToken.burn(tokensToBurn);

        // ensure tokens are burned
        assertEq(_wrappedToken.balanceOf(_tokenHolder), 0);
        assertEq(_wrappedToken.totalSupply(), totalTokenSupply - tokensToBurn);

        vm.revertTo(snapshot);

        address tokenBurner = makeAddr("tokenBurner");

        // approve tokens to token burner address
        _wrappedToken.approve(tokenBurner, tokensToBurn);
        
        // burn tokens
        changePrank(tokenBurner);
        _wrappedToken.burnFrom(_tokenHolder, tokensToBurn);

        // ensure tokens are burned
        assertEq(_wrappedToken.balanceOf(_tokenHolder), 0);
        assertEq(_wrappedToken.totalSupply(), totalTokenSupply - tokensToBurn);
    }

}
