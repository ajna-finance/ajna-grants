
const fs = require("fs");
const { defaultABICoder } = require("ethers").utils;


const Proposal = {
    proposalId: 0,   
    distributionId: 0,
    votesReceived: 0,
    tokensRequested: 0,
    fundingReceived: 0,
    succeeded: false,
    executed: false,
}

const proposalList = [
    {
        proposalId: 0,
        distributionId: 0,
        votesReceived: 0,
        tokensRequested: 0,
        fundingReceived: 0,
        succeeded: false,
        executed: false,
    },
    {
        proposalId: 1,
        distributionId: 0,
        votesReceived: 0,
        tokensRequested: 100,
        fundingReceived: 100,
        succeeded: false,
        executed: false,
    },
    {
        proposalId: 2,
        distributionId: 0,
        votesReceived: 0,
        tokensRequested: 200,
        fundingReceived: 200,
        succeeded: false,
        executed: false,
    },
    {
        proposalId: 3,
        distributionId: 0,
        votesReceived: 0,
        tokensRequested: 350,
        fundingReceived: 350,
        succeeded: false,
        executed: false,
    }
]

const budgetConstraint = 300

function solveProposalKnapsackBudgetConstraint(proposalList, budgetConstraint) {
    const matrix = [];
    for (let i = 0; i < proposalList.length; i++) {
        matrix[i] = [];
        for (let j = 0; j <= budgetConstraint; j++) {
            if (i === 0) {
                matrix[i][j] = 0;
            } else if (j === 0) {
                matrix[i][j] = 0;
            } else {
                matrix[i][j] = matrix[i - 1][j];
                if (proposalList[i].tokensRequested <= j) {
                    const value = matrix[i - 1][j - proposalList[i].tokensRequested] + proposalList[i].fundingReceived;
                    if (value > matrix[i][j]) {
                        matrix[i][j] = value;
                    }
                }
            }
        }
    }
    return matrix;
}

function topTenProposalsInKnapsack(proposalList, capacity) {
  const matrix = solveProposalKnapsackBudgetConstraint(proposalList, capacity);
  const result = [];
  let n = proposalList.length - 1;
  let w = capacity;
  while (n > 0) {
    if (matrix[n][w] !== 0 && matrix[n][w] !== matrix[n - 1][w]) {
      result.push(proposalList[n]);
      w = w - proposalList[n].tokensRequested;
    }
    n--;
  }
  return result;
}

console.log(topTenProposalsInKnapsack(proposalList, budgetConstraint));

// encode proposal list into hex string
function encodeProposalList(proposalList) {
    let encodedProposalList = "0x";
    for (let i = 0; i < proposalList.length; i++) {
        encodedProposalList += encodeProposal(proposalList[i]);
    }
    return encodedProposalList;
}


process.stdout.write(encodeProposalList(proposalList));