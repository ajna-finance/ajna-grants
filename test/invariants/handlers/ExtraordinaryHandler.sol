// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { console } from "@std/console.sol";
import { Test }     from "forge-std/Test.sol";
import { SafeCast } from "@oz/utils/math/SafeCast.sol";
import { Strings }  from "@oz/utils/Strings.sol";

import { GrantFund }        from "../../../src/grants/GrantFund.sol";
import { IStandardFunding } from "../../../src/grants/interfaces/IStandardFunding.sol";
import { Maths }            from "../../../src/grants/libraries/Maths.sol";

import { IAjnaToken }          from "../../utils/IAjnaToken.sol";
import { GrantFundTestHelper } from "../../utils/GrantFundTestHelper.sol";
import { Handler }             from "./Handler.sol";

contract ExtraordinaryHandler is Handler {

    /***********************/
    /*** State Variables ***/
    /***********************/

    // proposalId of extraordinary proposals executed
    uint256[] public proposalsExecuted;

    // proposalId of extraordinary proposals submitted
    uint256[] public proposals;

    struct VotingActor {
        ExtraordinaryVoteParams[] votes;
    }

    struct ExtraordinaryVoteParams {
        uint256 proposalId;
        uint256 votesCast;
    }

    mapping(address => VotingActor) internal votingActors; // actor => VotingActor
    mapping(uint256 => TestProposalExtraordinary) public testProposals; // proposalId => TestProposalExtraordinary

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(
        address payable grantFund_,
        address token_,
        address tokenDeployer_,
        uint256 numOfActors_,
        uint256 tokensToDistribute_,
        address testContract_
    ) Handler(grantFund_, token_, tokenDeployer_, numOfActors_, tokensToDistribute_, testContract_) {}

    /*************************/
    /*** Wrapped Functions ***/
    /*************************/

    function proposeExtraordinary(uint256 actorIndex_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['EH.proposeExtraordinary']++;
    }

    function voteExtraordinary(uint256 actorIndex_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['EH.voteExtraordinary']++;
    }

    function executeExtraordinary(uint256 actorIndex_) external useCurrentBlock useRandomActor(actorIndex_) {
        numberOfCalls['EH.executeExtraordinary']++;

        // TODO: get a random proposalId
        uint256 proposalId;

        // execute proposal
        // try _grantFund.executeExtraordinary(proposalId) returns (uint256 proposalId_) {
        //     // add executed proposalId to proposalsExecuted
        //     proposalsExecuted.push(proposalId_);
        // }
        // catch (bytes memory _err){
        //     bytes32 err = keccak256(_err);
        //     require(
        //         err == keccak256(abi.encodeWithSignature("ExecuteExtraordinaryProposalInvalid()")),
        //         UNEXPECTED_REVERT
        //     );
        // }
    }

    /**************************/
    /*** Utility Functions ****/
    /**************************/

    /**************************/
    /*** Logging Functions ****/
    /**************************/

    function logActorSummary(bool voteInfo_) external view {
        console.log("\nActor Summary\n");

        console.log("------------------");
        console.log("Number of Actors", getActorsCount());

        // sum proposal votes of each actor
        for (uint256 i = 0; i < getActorsCount(); ++i) {
            address actor = actors[i];

            console.log("------------");
            console.log("Actor:                    ", actor);
            console.log("Delegate:                 ", _ajna.delegates(actor));

            // log actor vote info if requested
            if (voteInfo_) {
                ExtraordinaryVoteParams[] memory extraorindaryVoteParams = getVotingActorsInfo(actor);

                for(uint256 j = 0; j < extraorindaryVoteParams.length; ++j) {
                    ExtraordinaryVoteParams memory voteParams = extraorindaryVoteParams[j];
                    console.log("--Vote----------");
                    console.log("proposalId: ", voteParams.proposalId);
                    console.log("votesCast:  ", voteParams.votesCast);
                }
            }
            console.log("------------");
            console.log("\n");
        }
    }

    function logCallSummary() external view {
        console.log("\nCall Summary\n");
        console.log("--EH----------");
        console.log("EH.proposeExtraordinary ",  numberOfCalls["EH.proposeExtraordinary"]);
        console.log("EH.voteExtraordinary    ",  numberOfCalls["EH.voteExtraordinary"]);
        console.log("EH.executeExtraordinary ",  numberOfCalls["EH.executeExtraordinary"]);
        console.log("roll                    ",  numberOfCalls["roll"]);
        console.log("------------------");
        console.log(
            "Total Calls:",
            numberOfCalls["EH.proposeExtraordinary"] +
            numberOfCalls["EH.voteExtraordinary"] +
            numberOfCalls["EH.executeExtraordinary"] +
            numberOfCalls["roll"]
        );
    }

    /****************************/
    /*** EH Getter Functions ****/
    /****************************/

    function getVotingActorsInfo(address actor_) public view returns (
        ExtraordinaryVoteParams[] memory
    ) {
        return votingActors[actor_].votes;
    }

}
