// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "forge-std/Test.sol";

import { AjnaToken, UUPSProxy } from "../src/Token.sol";

import { SigUtils }        from "./utils/SigUtils.sol";
import { TestAjnaTokenV2 } from "./utils/TestAjnaTokens.sol";

contract TokenTest is Test {

    // EIP1967 standard storage slot storing implementation address
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    using stdStorage for StdStorage;

    AjnaToken internal _token;
    AjnaToken internal _tokenProxyV1;
    SigUtils  internal _sigUtils;
    UUPSProxy proxy;

    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    function setUp() external {
        _token = new AjnaToken();

        proxy = new UUPSProxy(address(_token), "");

        // wrap in ABI to support easier calls
        _tokenProxyV1 = AjnaToken(address(proxy));

        _tokenProxyV1.initialize();
        _sigUtils = new SigUtils(_tokenProxyV1.DOMAIN_SEPARATOR());
    }

    function testCannotSendTokensToContract() external {
        vm.expectRevert("Cannot transfer tokens to the contract itself");
        _tokenProxyV1.transfer(address(_tokenProxyV1), 1);
    }

    function testTransferTokensToZeroAddress() external {
        vm.expectRevert("ERC20: transfer to the zero address");
        _tokenProxyV1.transfer(address(0), 1);
    }

    function invariantMetadata() external {
        assertEq(_tokenProxyV1.name(),     "AjnaToken");
        assertEq(_tokenProxyV1.symbol(),   "AJNA");
        assertEq(_tokenProxyV1.decimals(), 18);
    }

    function testChangeOwner() external {
        address newOwner = address(2222);

        assertEq(_tokenProxyV1.owner(), address(this));

        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(this), newOwner);
        _tokenProxyV1.transferOwnership(newOwner);

        assertEq(_tokenProxyV1.owner(), newOwner);
    }

    function testRenounceOwnership() external {
        assertEq(_tokenProxyV1.owner(), address(this));

        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(this), address(0));
        _tokenProxyV1.renounceOwnership();

        assertEq(_tokenProxyV1.owner(), address(0));

        TestAjnaTokenV2 tokenV2 = new TestAjnaTokenV2();
        // check upgrade is not possible
        vm.expectRevert("Ownable: caller is not the owner");
        _tokenProxyV1.upgradeTo(address(tokenV2));

        // check no ownable actions are possible
        vm.expectRevert("Ownable: caller is not the owner");
        _tokenProxyV1.transferOwnership(address(2222));
    }

    function testTokenTotalSupply() external {
        assertEq(_tokenProxyV1.totalSupply(), 1_000_000_000 * 10 ** _tokenProxyV1.decimals());
    }

    function testMultipleInitialization() external {
        // should revert if token already initialized
        vm.expectRevert("Initializable: contract is already initialized");
        _tokenProxyV1.initialize();
    }

    function testMinterTokenBalance() external {
        assertEq(_tokenProxyV1.balanceOf(address(this)), 1_000_000_000 * 10 **18);
    }

    function testCantMint() external {
        AjnaTokenMintable mintableToken = new AjnaTokenMintable();
        AjnaToken mintableTokenProxy = AjnaToken(address(new UUPSProxy(address(mintableToken), "")));
        mintableTokenProxy.initialize();

        assertEq(mintableTokenProxy.totalSupply(), 1_000_000_000 * 1e18);

        vm.expectRevert("Initializable: contract is not initializing");
        mintableToken.mint(address(1111), 10 * 1e18);
    }

    function testBurn() external {
        assertEq(_tokenProxyV1.totalSupply(), 1_000_000_000 * 10 ** _tokenProxyV1.decimals());
        _tokenProxyV1.burn(50_000_000 * 10 ** 18);
        assertEq(_tokenProxyV1.totalSupply(), 950_000_000 * 10 ** _tokenProxyV1.decimals());
    }

    function testTransferWithApprove(uint256 amount_) external {
        vm.assume(amount_ > 0);
        vm.assume(amount_ <= 1_000_000_000 * 10 ** _tokenProxyV1.decimals());
        _tokenProxyV1.approve(address(this), amount_);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), address(5555), amount_);
        _tokenProxyV1.transferFrom(address(this), address(5555), amount_);

        assertEq(_tokenProxyV1.balanceOf(address(this)),  1_000_000_000 * 10 ** _tokenProxyV1.decimals() - amount_);
        assertEq(_tokenProxyV1.balanceOf(address(5555)), amount_);
    }

    function testTransferWithPermit(uint256 amount_) external {
        vm.assume(amount_ > 0);
        vm.assume(amount_ <= 1_000_000_000 * 10 ** _tokenProxyV1.decimals());

        // define owner and spender addresses
        (address owner, uint256 ownerPrivateKey) = makeAddrAndKey("owner");
        address spender                          = makeAddr("spender");

        // set owner balance to 1_000 AJNA tokens
        deal(address(_tokenProxyV1), owner, amount_);

        // check owner and spender balances
        assertEq(_tokenProxyV1.balanceOf(owner),   amount_);
        assertEq(_tokenProxyV1.balanceOf(spender), 0);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: amount_,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = _sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        _tokenProxyV1.permit(permit.owner, permit.spender, permit.value, permit.deadline, v, r, s);

        vm.prank(spender);
        _tokenProxyV1.transferFrom(owner, spender, amount_);

        // check owner and spender balances after transfer
        assertEq(_tokenProxyV1.balanceOf(owner),   0);
        assertEq(_tokenProxyV1.balanceOf(spender), amount_);

        assertEq(_tokenProxyV1.allowance(owner, spender), 0);
    }

    function testDelegateVotes() external {
        address delegator = address(2222);
        address delegate1 = address(3333);
        address delegate2 = address(4444);

        // set delegator balance to 1_000 AJNA tokens
        deal(address(_tokenProxyV1), delegator, 1_000 * 10 ** 18);

        // check voting power
        assertEq(_tokenProxyV1.getVotes(delegator), 0);
        assertEq(_tokenProxyV1.getVotes(delegate1), 0);
        assertEq(_tokenProxyV1.getVotes(delegate2), 0);

        vm.roll(11111);
        vm.prank(delegator);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator, address(0), delegate1);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegate1, 0, 1_000 * 10 ** 18);
        _tokenProxyV1.delegate(delegate1);

        // check accounts balances
        assertEq(_tokenProxyV1.balanceOf(delegator), 1_000 * 10 **18);
        assertEq(_tokenProxyV1.balanceOf(delegate1), 0);
        assertEq(_tokenProxyV1.balanceOf(delegate2), 0);
        // check voting power
        assertEq(_tokenProxyV1.getVotes(delegator), 0);
        assertEq(_tokenProxyV1.getVotes(delegate1), 1_000 * 10 **18);
        assertEq(_tokenProxyV1.getVotes(delegate2), 0);

        assertEq(_tokenProxyV1.delegates(delegator), delegate1);

        vm.roll(11112);

        vm.prank(delegator);
        vm.expectEmit(true, true, false, true);
        emit DelegateChanged(delegator, delegate1, delegate2);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegate1, 1_000 * 10 ** 18, 0);
        vm.expectEmit(true, true, false, true);
        emit DelegateVotesChanged(delegate2, 0, 1_000 * 10 ** 18);
        _tokenProxyV1.delegate(delegate2);
        vm.roll(11113);

        // check accounts balances
        assertEq(_tokenProxyV1.balanceOf(delegator), 1_000 * 10 **18);
        assertEq(_tokenProxyV1.balanceOf(delegate1), 0);
        assertEq(_tokenProxyV1.balanceOf(delegate2), 0);
        // check voting power
        assertEq(_tokenProxyV1.getVotes(delegator), 0);
        assertEq(_tokenProxyV1.getVotes(delegate1), 0);
        assertEq(_tokenProxyV1.getVotes(delegate2), 1_000 * 10 **18);

        assertEq(_tokenProxyV1.delegates(delegator), delegate2);
        // check voting power at block 11111 and 11112
        assertEq(_tokenProxyV1.getPastVotes(delegate1, 11111), 1_000 * 10 **18);
        assertEq(_tokenProxyV1.getPastVotes(delegate2, 11111), 0);
        assertEq(_tokenProxyV1.getPastVotes(delegate1, 11112), 0);
        assertEq(_tokenProxyV1.getPastVotes(delegate2, 11112), 1_000 * 10 **18);
    }

    // TODO: implement this
    function testVote() external {
        // TODO: should we implement this by actually simulate voting?
    }

    function testCalculateVotingPower() external {
        address delegator1 = address(1111);
        address delegator2 = address(2222);
        address delegate1  = address(3333);
        address delegate2  = address(4444);

        // set delegators and delegates AJNA balances
        deal(address(_tokenProxyV1), delegator1, 1_000 * 10 ** 18);
        deal(address(_tokenProxyV1), delegator2, 2_000 * 10 ** 18);
        deal(address(_tokenProxyV1), delegate1,  3_000 * 10 ** 18);
        deal(address(_tokenProxyV1), delegate2,  4_000 * 10 ** 18);

        // initial voting power is 0
        assertEq(_tokenProxyV1.getVotes(delegator1), 0);
        assertEq(_tokenProxyV1.getVotes(delegator2), 0);
        assertEq(_tokenProxyV1.getVotes(delegate1),  0);
        assertEq(_tokenProxyV1.getVotes(delegate2),  0);

        // delegates delegate to themselves
        vm.prank(delegate1);
        _tokenProxyV1.delegate(delegate1);
        vm.prank(delegate2);
        _tokenProxyV1.delegate(delegate2);

        // check votes
        assertEq(_tokenProxyV1.getVotes(delegator1), 0);
        assertEq(_tokenProxyV1.getVotes(delegator2), 0);
        assertEq(_tokenProxyV1.getVotes(delegate1),  3_000 * 10 ** 18);
        assertEq(_tokenProxyV1.getVotes(delegate2),  4_000 * 10 ** 18);

        // delegators delegate to delegates
        vm.prank(delegator1);
        _tokenProxyV1.delegate(delegate1);
        vm.prank(delegator2);
        _tokenProxyV1.delegate(delegate2);

        // check votes
        assertEq(_tokenProxyV1.getVotes(delegator1), 0);
        assertEq(_tokenProxyV1.getVotes(delegator2), 0);
        assertEq(_tokenProxyV1.getVotes(delegate1),  4_000 * 10 ** 18);
        assertEq(_tokenProxyV1.getVotes(delegate2),  6_000 * 10 ** 18);

        assertEq(_tokenProxyV1.delegates(delegator1), delegate1);
        assertEq(_tokenProxyV1.delegates(delegator2), delegate2);
        assertEq(_tokenProxyV1.delegates(delegate1),  delegate1);
        assertEq(_tokenProxyV1.delegates(delegate2),  delegate2);
    }

    function testNestedDelegation() external {
        assertEq(_tokenProxyV1.getVotes(address(this)), 0);
        assertEq(_tokenProxyV1.getVotes(address(3333)), 0);
        assertEq(_tokenProxyV1.getVotes(address(4444)), 0);

        // tokens owner delegates votes to 3333
        vm.roll(11112);
        _tokenProxyV1.delegate(address(3333));

        assertEq(_tokenProxyV1.getVotes(address(this)), 0);
        assertEq(_tokenProxyV1.getVotes(address(3333)), 1_000_000_000 * 10 **18);
        assertEq(_tokenProxyV1.getVotes(address(4444)), 0);

        // 3333 cannot delegate votes to 4444
        vm.roll(11112);
        vm.prank(address(3333));
        _tokenProxyV1.delegate(address(4444));

        assertEq(_tokenProxyV1.getVotes(address(this)), 0);
        assertEq(_tokenProxyV1.getVotes(address(3333)), 1_000_000_000 * 10 **18);
        assertEq(_tokenProxyV1.getVotes(address(4444)), 0);

        // tokens owner delegates votes to 4444
        _tokenProxyV1.delegate(address(4444));

        assertEq(_tokenProxyV1.getVotes(address(this)), 0);
        assertEq(_tokenProxyV1.getVotes(address(3333)), 0);
        assertEq(_tokenProxyV1.getVotes(address(4444)), 1_000_000_000 * 10 **18);
    }

    function testUpgradeOnlyOwner() external {
        TestAjnaTokenV2 tokenV2 = new TestAjnaTokenV2();

        vm.prank(address(2222));
        vm.expectRevert("Ownable: caller is not the owner");
        _tokenProxyV1.upgradeTo(address(tokenV2));

        _tokenProxyV1.transferOwnership(address(2222));

        vm.prank(address(2222));
        vm.expectEmit(true, true, false, true);
        emit Upgraded(address(tokenV2));
        _tokenProxyV1.upgradeTo(address(tokenV2));
    }

    function testCanUpgrade() external {
        // verify initial state
        assertEq(_tokenProxyV1.totalSupply(), 1_000_000_000 * 10 ** _tokenProxyV1.decimals());
        // TODO: check initial implementation slot as part of testing implementation address access vs proxy
        // assertEq(_tokenProxyV1.proxiableUUID())
        // emit log_address(stdStorage.read_address(_tokenProxyV1.proxiableUUID()));
        // emit log_address(address(uint160(uint256(_tokenProxyV1.proxiableUUID()))));

        // transfer some tokens to another address
        address newTokenHolder = address(1111);
        uint256 tokensTransferred = 1000;
        _tokenProxyV1.approve(address(this), tokensTransferred);
        _tokenProxyV1.transferFrom(address(this), newTokenHolder, tokensTransferred);

        TestAjnaTokenV2 tokenV2 = new TestAjnaTokenV2();
        vm.expectEmit(true, true, false, true);
        emit Upgraded(address(tokenV2));
        _tokenProxyV1.upgradeTo(address(tokenV2));

        // re-wrap the proxy
        TestAjnaTokenV2 tokenProxyV2 = TestAjnaTokenV2(address(proxy));

        // check different implementation addresses
        assertTrue(address(_token) != address(tokenV2));
        // check proxy address is unchanged
        assertEq(address(_tokenProxyV1), address(tokenProxyV2));
        assertEq(address(_tokenProxyV1), address(proxy));
        assertEq(address(tokenProxyV2),  address(proxy));

        // check new method can be accessed and correctly reads state
        assertEq(tokenProxyV2.testVar(), 0);
        tokenProxyV2.setTestVar(100);
        assertEq(tokenProxyV2.testVar(), 100);

        // check previous state unchanged
        assertEq(tokenProxyV2.name(),     "AjnaToken");
        assertEq(tokenProxyV2.symbol(),   "AJNA");
        assertEq(tokenProxyV2.decimals(), 18);

        assertEq(tokenProxyV2.totalSupply(),             1_000_000_000 * 10 ** tokenProxyV2.decimals());
        assertEq(tokenProxyV2.balanceOf(address(this)),  1_000_000_000 * 10 ** tokenProxyV2.decimals() - tokensTransferred);
        assertEq(tokenProxyV2.balanceOf(newTokenHolder), tokensTransferred);
    }

    // TODO: record storage variables layout and check upgrade can take place without messing up storage layout
    // relevant docs: https://book.getfoundry.sh/reference/forge-std/std-storage?highlight=storage#std-storage
    function testUpgradeStorageLayout() external {

        // // TODO: check before and after storage layout
        // stdStorage.target(address(tokenProxyV1))
        //     .sig() // function signature
        //     .with_key() // function arg
        //     .read_uint(); // check type 
    }

    function testRemoveUpgradeability() external {
        // TODO: is OK to suppose that upgradeability can be removed by renouncing to ownership?
    }

}

contract AjnaTokenMintable is AjnaToken {
    function mint(address to_, uint256 amount_) external {
        super._mint(to_, amount_);
    }
}
