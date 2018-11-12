pragma solidity ^0.4.24;

import "Registry.sol";
import "token/minime/MiniMeToken.sol";
import "math/SafeMath.sol";
import "registryentry/RegistryEntryLib.sol";
/**
 * @title Contract created with each submission to a TCR
 *
 * @dev It contains all state and logic related to TCR challenging and voting
 * Full copy of this contract is NOT deployed with each submission in order to save gas. Only forwarder contracts
 * pointing into single intance of it.
 * This contract is meant to be extended by domain specific registry entry contracts (District, ParamChange)
 */

contract RegistryEntry is ApproveAndCallFallBack {
  using SafeMath for uint;
  using RegistryEntryLib for RegistryEntryLib.Challenge;

  Registry internal constant registry = Registry(0xfEEDFEEDfeEDFEedFEEdFEEDFeEdfEEdFeEdFEEd);
  MiniMeToken internal constant registryToken = MiniMeToken(0xDeaDDeaDDeaDDeaDDeaDDeaDDeaDDeaDDeaDDeaD);

  enum Status {ChallengePeriod, CommitPeriod, RevealPeriod, Blacklisted, Whitelisted}

  address internal creator;
  uint internal version;
  uint internal deposit;
  uint internal challengePeriodEnd;

  RegistryEntryLib.Challenge[] internal challenges;

  // Challenge[] public challenges;

  /**
   * @dev Modifier that disables function if registry is in emergency state
   */
  modifier notEmergency() {
    require(!registry.isEmergency());
    _;
  }

  /**
   * @dev Modifier that disables function if registry is not in whitelisted state
   */
  // modifier onlyWhitelisted() {
  //   require(isWhitelisted());
  //   _;
  // }

  function isChallengePeriodActive()
    internal
    constant
    returns (bool) {
    return now <= challengePeriodEnd;
  }

  /**
   * @dev Constructor for this contract.
   * Native constructor is not used, because users create only forwarders into single instance of this contract,
   * therefore constructor must be called explicitly.
   * Must NOT be callable multiple times
   * Transfers TCR entry token deposit from sender into this contract

   * @param _creator Creator of a district
   * @param _version Version of District contract
   */
  function construct(
    address _creator,
    uint _version
  )
  public
  {
    require(challengePeriodEnd == 0);
    deposit = registry.db().getUIntValue(registry.depositKey());
    require(registryToken.transferFrom(msg.sender, this, deposit));
    challengePeriodEnd = now.add(registry.db().getUIntValue(registry.challengePeriodDurationKey()));
    creator = _creator;
    version = _version;
  }

  /**
   * @dev Creates a challenge for this TCR entry
   * Must be within challenge period
   * Entry can be challenged only once
   * Transfers token deposit from challenger into this contract
   * Forks registry token (DankToken) in order to create single purpose voting token to vote about this challenge

   * @param _challenger Address of a challenger
   * @param _challengeMetaHash IPFS hash of meta data related to this challenge
   */
  function createChallenge(
    address _challenger,
    bytes _challengeMetaHash
  )
  public
  notEmergency
  {
    require(isChallengeable());
    require(registryToken.transferFrom(_challenger, this, deposit));

    RegistryEntryLib.Challenge memory challenge;

    challenge.challenger = _challenger;
    challenge.voteQuorum = registry.db().getUIntValue(registry.voteQuorumKey());
    uint commitDuration = registry.db().getUIntValue(registry.commitPeriodDurationKey());
    uint revealDuration = registry.db().getUIntValue(registry.revealPeriodDurationKey());
    
    challenge.commitPeriodEnd = now.add(commitDuration);
    challenge.revealPeriodEnd = challenge.commitPeriodEnd.add(revealDuration);
    challenge.rewardPool = ((100 - registry.db()
      .getUIntValue(
      registry.challengeDispensationKey()
      )
    ).mul(deposit)) / 100;
    challenge.metaHash = _challengeMetaHash;
    challenge.creationBlock = block.number;
    challenges.push(challenge);
    registry.fireChallengeCreatedEvent(version,
                                       challenge.challenger,
                                       challenge.commitPeriodEnd,
                                       challenge.revealPeriodEnd,
                                       challenge.rewardPool,
                                       challenge.metaHash);
  }

  function isChallengeable() internal constant returns (bool) {
    return isChallengePeriodActive() && challenges.length == 0;
  }

  function currentChallengeIndex() internal constant returns (uint) {
    return challenges.length - 1;
  }

  function currentChallenge() internal returns (RegistryEntryLib.Challenge storage) {
    return challenges[currentChallengeIndex()];
  }

  /**
   * @dev Commits encrypted vote to challenged entry
   * Locks voter's tokens in this contract. Returns when vote is revealed
   * Must be within commit period
   * Voting takes full balance of voter's voting token

   * @param _voter Address of a voter
   * @param _amount Amount of tokens to vote with
   * @param _secretHash Encrypted vote option with salt. sha3(voteOption, salt)
   */
  function commitVote(
    uint _challengeIndex,
    address _voter,
    uint _amount,
    bytes32 _secretHash
  )
  external
  notEmergency
  {
    RegistryEntryLib.Challenge storage challenge = challenges[_challengeIndex];
    require(challenge.isVoteCommitPeriodActive());
    require(_amount > 0);
    require(!challenge.hasVoted(_voter));
    require(registryToken.transferFrom(_voter, this, _amount));
    challenge.vote[_voter].secretHash = _secretHash;
    challenge.vote[_voter].amount = _amount;

    // TODO add challenge index
    registry.fireVoteCommittedEvent(version,
                                    _voter,
                                    challenge.vote[_voter].amount);
  }

  /**
   * @dev Reveals previously committed vote
   * Returns registryToken back to the voter
   * Must be within reveal period

   * @param _voteOption Vote option voter previously voted with
   * @param _salt Salt with which user previously encrypted his vote option
   */
  function revealVote(
    uint _challengeIndex,
    RegistryEntryLib.VoteOption _voteOption,
    string _salt
  )
  external
  notEmergency
  {
    address _voter=msg.sender;
    RegistryEntryLib.Challenge storage challenge = challenges[_challengeIndex];
    require(challenge.isVoteRevealPeriodActive());
    require(keccak256(abi.encodePacked(uint(_voteOption), _salt)) == challenge.vote[_voter].secretHash);
    require(!challenge.isVoteRevealed(_voter));

    challenge.vote[_voter].revealedOn = now;
    uint amount = challenge.vote[_voter].amount;
    require(registryToken.transfer(_voter, amount));
    challenge.vote[_voter].option = _voteOption;

    if (_voteOption == RegistryEntryLib.VoteOption.Include) {
      challenge.votesInclude = challenge.votesInclude.add(amount);
    } else if (_voteOption == RegistryEntryLib.VoteOption.Exclude) {
      challenge.votesExclude = challenge.votesExclude.add(amount);
    } else {
      revert();
    }

    registry.fireVoteRevealedEvent(version,
                                   _voter,
                                   uint(challenge.vote[_voter].option));



    // require(isVoteRevealPeriodActive());
    // Challenge challenge = currentChallenge();
    // require(sha3(uint(_voteOption), _salt) == challenge.vote[msg.sender].secretHash);
    // require(!isVoteRevealed(msg.sender));

    // challenge.vote[msg.sender].revealedOn = now;
    // uint amount = challenge.vote[msg.sender].amount;
    // require(registryToken.transfer(msg.sender, amount));
    // challenge.vote[msg.sender].option = _voteOption;
    // if (_voteOption == VoteOption.Include) {
    //   challenge.votesInclude = challenge.votesInclude.add(amount);
    // } else if (_voteOption == VoteOption.Exclude) {
    //   challenge.votesExclude = challenge.votesExclude.add(amount);
    // } else {
    //   revert();
    // }

    // var eventData = new uint[](2);
    // eventData[0] = currentChallengeIndex();
    // eventData[1] = uint(msg.sender);
    // registry.fireRegistryEntryEvent("voteRevealed", version, eventData);
  }

  /**
   * @dev Refunds vote deposit after reveal period
   * Can be called by anybody, to claim voter's reward to him
   * Can't be called if vote was revealed
   * Can't be called twice for the same vote
   * @param _voter Address of a voter
   */
  function reclaimVoteAmount(uint _challengeIndex, address _voter)
    public
    notEmergency {

    /* if (_voter == 0x0) { */
    /*   _voter = msg.sender; */
    /* } */
    RegistryEntryLib.Challenge storage challenge = currentChallenge();
    require(challenge.isVoteRevealPeriodOver());
    require(!challenge.isVoteRevealed(_voter));
    require(!challenge.isVoteAmountReclaimed(_voter));

    uint amount = challenge.vote[_voter].amount;
    require(registryToken.transfer(_voter, amount));

    challenge.vote[_voter].reclaimedVoteAmountOn = now;

    registry.fireVoteAmountClaimedEvent(version, _voter);
  }

  /**
   * @dev Claims vote reward after reveal period
   * Voter has reward only if voted for winning option
   * Voter has reward only when revealed the vote
   * Can be called by anybody, to claim voter's reward to him
   * @param _voter Address of a voter
   */
  function claimVoteReward(uint _challengeIndex, address _voter)
    external
    notEmergency
  {

    /* if (_voter == 0x0) { */
    /*   _voter = msg.sender; */
    /* } */
    RegistryEntryLib.Challenge storage challenge = currentChallenge();
    require(challenge.isVoteRevealPeriodOver());
    require(!challenge.isVoteRewardClaimed(_voter));
    require(challenge.isVoteRevealed(_voter));
    require(challenge.votedWinningVoteOption(_voter));

    uint reward = challenge.voteReward(_voter);

    require(reward > 0);
    require(registryToken.transfer(_voter, reward));
    challenge.vote[_voter].claimedRewardOn = now;

    registry.fireVoteRewardClaimedEvent(version,
                                        _voter,
                                        reward);
  }

  /**
   * @dev Claims challenger's reward after reveal period
   * Challenger has reward only if winning option is Exclude
   * Can be called by anybody, to claim challenger's reward to him/her
   */
  function claimChallengeReward(uint _challengeIndex)
    external
    notEmergency
  {
    RegistryEntryLib.Challenge storage challenge = challenges[_challengeIndex];
    require(challenge.isVoteRevealPeriodOver());
    require(!challenge.isChallengeRewardClaimed());
    require(!challenge.isWinningOptionInclude());
    require(registryToken.transfer(challenge.challenger, challenge.challengeReward(deposit)));

    challenge.claimedRewardOn = now;

    registry.fireChallengeRewardClaimedEvent(version,
                                             challenge.challenger,
                                             challenge.challengeReward(deposit));
  }


  /**
   * @dev Function called by MiniMeToken when somebody calls approveAndCall on it.
   * This way token can be transferred to a recipient in a single transaction together with execution
   * of additional logic
   * @param _from Sender of transaction approval
   * @param _amount Amount of approved tokens to transfer
   * @param _token Token that received the approval
   * @param _data Bytecode of a function and passed parameters, that should be called after token approval
   */
  function receiveApproval(
                           address _from,
                           uint256 _amount,
                           address _token,
                           bytes _data)
    public
  {
    require(address(this).call(_data));
  }

  ///////////////////////////////////////////////
  /////////////////////////////////////////////
  /////////////////////////////////////////
  /**
   * @dev Claims vote reward after reveal period
   * Voter has reward only if voted for winning option
   * Voter has reward only when revealed the vote
   * Can be called by anybody, to claim voter's reward to him

   * @param _voter Address of a voter
   */
  // function claimVoteReward(address _voter) public {
  //   claimVoteRewardNth(currentChallengeIndex(), _voter);
  // }
  // function claimVoteRewardNth(
  //   uint _challengeIndex,
  //   address _voter
  // )
  // public
  // notEmergency
  // {
  //   if (_voter == 0x0) {
  //     _voter = msg.sender;
  //   }
  //   require(isVoteRevealPeriodOverNth(_challengeIndex));
  //   require(!isVoteRewardClaimedNth(_challengeIndex, _voter));
  //   require(isVoteRevealedNth(_challengeIndex, _voter));
  //   uint reward = voteRewardNth(_challengeIndex, _voter);
  //   require(reward > 0);
  //   require(registryToken.transfer(_voter, reward));

  //   challenges[_challengeIndex].vote[_voter].claimedRewardOn = now;

  //   var eventData = new uint[](2);
  //   eventData[0] = _challengeIndex;
  //   eventData[1] = uint(_voter);
  //   registry.fireRegistryEntryEvent("voteRewardClaimed", version, eventData);
  // }

  /**
   * @dev Claims challenger's reward after reveal period
   * Challenger has reward only if winning option is Exclude
   * Can be called by anybody, to claim challenger's reward to him/her
   */
  // function claimChallengeReward() public {
  //   claimChallengeRewardNth(currentChallengeIndex());
  // }
  // function claimChallengeRewardNth(uint _challengeIndex)
  // public
  // notEmergency
  // {
  //   require(isVoteRevealPeriodOverNth(_challengeIndex));
  //   require(!isEntryRewardClaimedNth(_challengeIndex));
  //   require(!isWinningOptionIncludeNth(_challengeIndex));

  //   Challenge storage challenge = challenges[_challengeIndex]; 
  //   require(registryToken.transfer(challenge.challenger, entryRewardNth(_challengeIndex)));
  //   challenge.claimedRewardOn = now;

  //   var eventData = new uint[](1);
  //   eventData[0] = _challengeIndex;
  //   registry.fireRegistryEntryEvent("challengeRewardClaimed", version, eventData);
  // }

  /**
   * @dev Claims creator's reward after reveal period
   * Creator has reward only if winning option is Include
   * Can be called by anybody, to claim creator's reward to him/her
   */
  // function claimCreatorReward() public {
  //   claimCreatorRewardNth(currentChallengeIndex());
  // }
  // function claimCreatorRewardNth(uint _challengeIndex)
  // public
  // notEmergency
  // {
  //   require(isVoteRevealPeriodOverNth(_challengeIndex));
  //   require(!isEntryRewardClaimedNth(_challengeIndex));
  //   require(isWinningOptionIncludeNth(_challengeIndex));

  //   Challenge storage challenge = challenges[_challengeIndex]; 
  //   require(registryToken.transfer(creator, entryRewardNth(_challengeIndex)));
  //   challenge.claimedRewardOn = now;

  //   var eventData = new uint[](1);
  //   eventData[0] = _challengeIndex;
  //   registry.fireRegistryEntryEvent("creatorRewardClaimed", version, eventData);
  // }

  /**
   * @dev Function called by MiniMeToken when somebody calls approveAndCall on it.
   * This way token can be transferred to a recipient in a single transaction together with execution
   * of additional logic

   * @param _from Sender of transaction approval
   * @param _amount Amount of approved tokens to transfer
   * @param _token Token that received the approval
   * @param _data Bytecode of a function and passed parameters, that should be called after token approval
   */
  // function receiveApproval(
  //   address _from,
  //   uint256 _amount,
  //   address _token,
  //   bytes _data)
  // public
  // {
  //   require(this.call(_data));
  // }

  /**
   * @dev Returns current status of a registry entry

   * @return Status
   */

  // function status() public constant returns (Status) {
  //   return statusNth(currentChallengeIndex());   
  // }
   
  // function statusNth(uint _challengeIndex) public constant returns (Status) {
  //   if (isBlacklistedNth(_challengeIndex)) {
  //     return Status.Blacklisted;
  //   } else if (isWhitelistedNth(_challengeIndex)) {
  //     return Status.Whitelisted;
  //   } else if (isChallengePeriodActive() && !wasChallenged()) {
  //     return Status.ChallengePeriod;
  //   } else if (isVoteRevealPeriodActiveNth(_challengeIndex)) {
  //     return Status.RevealPeriod;
  //   } else if (isVoteCommitPeriodActiveNth(_challengeIndex)) {
  //     return Status.CommitPeriod;
  //   }
  // }

  // function isChallengePeriodActive() internal constant returns (bool) {
  //   return now <= challengePeriodEnd;
  // }

  // function isWhitelisted() public constant returns (bool) {
  //   return isWhitelistedNth(currentChallengeIndex());
  // }
  // function isWhitelistedNth(uint _challengeIndex) public constant returns (bool) {
  //   return isVoteRevealPeriodOverNth(_challengeIndex) && isWinningOptionIncludeNth(_challengeIndex);
  // }

  // function isBlacklisted() public constant returns (bool) {
  //   return isBlacklistedNth(currentChallengeIndex());
  // }
  // function isBlacklistedNth(uint _challengeIndex) public constant returns (bool) {
  //   return isVoteRevealPeriodOverNth(_challengeIndex) && !isWinningOptionIncludeNth(_challengeIndex);
  // }

  /**
   * @dev Returns date when registry entry was whitelisted
   * Since this doesn't happen with any transaction, it's the reveal period end

   * @return UNIX time of whitelisting
   */
  // function whitelistedOn() public constant returns (uint) { 
  //   return whitelistedOnNth(currentChallengeIndex());
  // }
  // function whitelistedOnNth(uint _challengeIndex) public constant returns (uint) {
  //   if (!isWhitelistedNth(_challengeIndex)) {
  //     return 0;
  //   }
  //   return challenges[_challengeIndex].revealPeriodEnd;
  // }

  // function wasChallenged() public constant returns (bool) {
  //   return challenges.length != 0;
  // }
  // function isChallenged() internal constant returns (bool) {
  //   return challenges.length != 0 && ;
  // }
  // function isVoteCommitPeriodActive() public constant returns (bool) {
  //   return isVoteCommitPeriodActiveNth(currentChallengeIndex());
  // }
  // function isVoteCommitPeriodActiveNth(uint _challengeIndex) public constant returns (bool) {
  //   if (challenges.length == 0) {
  //     return false;
  //   }
  //   return now <= challenges[_challengeIndex].commitPeriodEnd;
  // }

  // function isVoteRevealPeriodActive() public constant returns (bool) {
  //   return isVoteRevealPeriodActiveNth(currentChallengeIndex());
  // }
  // function isVoteRevealPeriodActiveNth(uint _challengeIndex) public constant returns (bool) {
  //   if (challenges.length == 0) {
  //     return false;
  //   }
  //   return !isVoteCommitPeriodActiveNth(_challengeIndex) && now <= challenges[_challengeIndex].revealPeriodEnd;
  // }

  // function isVoteRevealPeriodOver() public constant returns (bool) {
  //   return isVoteRevealPeriodOverNth(currentChallengeIndex());
  // }
  // function isVoteRevealPeriodOverNth(uint _challengeIndex) public constant returns (bool) {
  //   if (challenges.length == 0) {
  //     return false;
  //   }
  //   Challenge storage challenge = challenges[_challengeIndex];
  //   return challenge.revealPeriodEnd > 0 && now > challenge.revealPeriodEnd;
  // }

  // function isVoteRevealed(address _voter) public constant returns (bool) {
  //   return isVoteRevealedNth(currentChallengeIndex(), _voter);
  // }
  // function isVoteRevealedNth(uint _challengeIndex, address _voter) public constant returns (bool) {
  //   return challenges[_challengeIndex].vote[_voter].revealedOn > 0;
  // }

  // function isVoteRewardClaimed(address _voter) public constant returns (bool) {
  //   return isVoteRewardClaimedNth(currentChallengeIndex(), _voter);
  // }
  // function isVoteRewardClaimedNth(uint _challengeIndex, address _voter) public constant returns (bool) {
  //   return challenges[_challengeIndex].vote[_voter].claimedRewardOn > 0;
  // }

  // function isEntryRewardClaimed() public constant returns (bool) {
  //   return isEntryRewardClaimedNth(currentChallengeIndex());
  // }
  // function isEntryRewardClaimedNth(uint _challengeIndex) public constant returns (bool) {
  //   return challenges[_challengeIndex].claimedRewardOn > 0;
  // }


  /**
   * @dev Returns winning vote option in held voting according to vote quorum
   * If voteQuorum is 50, any majority of votes will win
   * If voteQuorum is 24, only 25 votes out of 100 is enough to Include be winning option
   *
   * @return Winning vote option
   */
  // function winningVoteOption() public constant returns (VoteOption) {
  //   return winningVoteOptionNth(currentChallengeIndex());
  // }
  // function winningVoteOptionNth(uint _challengeIndex) public constant returns (VoteOption) {
  //   if (!isVoteRevealPeriodOverNth(_challengeIndex)) {
  //     return VoteOption.Neither;
  //   }
  //   uint include = votesIncludeNth(_challengeIndex);
  //   uint exclude = votesExcludeNth(_challengeIndex);
  //   Challenge challenge = currentChallenge();
  //   if (include.mul(100) >= challenge.voteQuorum.mul(include.add(exclude))) {
  //     return VoteOption.Include;
  //   } else {
  //     return VoteOption.Exclude;
  //   }
  // }

  // function votesIncludeNth(uint _challengeIndex) internal view returns (uint) {
  //   return challenges[_challengeIndex].votesInclude;
  // }

  // function votesExcludeNth(uint _challengeIndex) internal view returns (uint) {
  //   return challenges[_challengeIndex].votesExclude;
  // }

  /**
   * @dev Returns whether Include is winning vote option
   *
   * @return True if Include is winning option
   */
  // function isWinningOptionInclude() public constant returns (bool) {
  //   return isWinningOptionIncludeNth(currentChallengeIndex());
  // }
  // function isWinningOptionIncludeNth(uint _challengeIndex) public constant returns (bool) {
  //   return winningVoteOptionNth(_challengeIndex) == VoteOption.Include;
  // }

  /**
   * @dev Returns amount of votes for winning vote option
   *
   * @return Amount of votes
   */
  // function winningVotesAmount() public constant returns (uint) {
  //   return winningVotesAmountNth(currentChallengeIndex());
  // }
  // function winningVotesAmountNth(uint _challengeIndex) public constant returns (uint) {
  //   uint include = votesIncludeNth(_challengeIndex);
  //   uint exclude = votesExcludeNth(_challengeIndex);
  //   if (include >= exclude) {
  //     return include;
  //   } else {
  //     return exclude;
  //   }
  // }

  // function voterVotesInclude(address _voter) public constant returns (uint) {
  //   return voterVotesIncludeNth(currentChallengeIndex(), _voter);
  // }
  // function voterVotesIncludeNth(uint _challengeIndex, address _voter) public constant returns (uint) {
  //   Challenge storage challenge = challenges[_challengeIndex];
  //   Vote storage vote = challenge.vote[_voter];
  //   if (vote.option == VoteOption.Include) {
  //     return vote.amount;
  //   } else {
  //     return 0;
  //   }
  // }

  // function voterVotesExclude(address _voter) public constant returns (uint) {
  //   return voterVotesIncludeNth(currentChallengeIndex(), _voter);
  // }
  // function voterVotesExcludeNth(uint _challengeIndex, address _voter) public constant returns (uint) {
  //   Challenge storage challenge = challenges[_challengeIndex];
  //   Vote storage vote = challenge.vote[_voter];
  //   if (vote.option == VoteOption.Exclude) {
  //     return vote.amount;
  //   } else {
  //     return 0;
  //   }
  // }

  /**
   * @dev Returns token reward amount belonging to a voter for voting for a winning option
   * @param _voter Address of a voter
   *
   * @return Amount of tokens
   */
  // function voteReward(address _voter) public constant returns (uint) {
  //   return voteRewardNth(currentChallengeIndex(), _voter);
  // }
  // function voteRewardNth(uint _challengeIndex, address _voter) public constant returns (uint) {
  //   uint winningAmount = winningVotesAmountNth(_challengeIndex);
  //   VoteOption winningOption = winningVoteOptionNth(_challengeIndex);
  //   uint voterAmount = 0;
  //   if (winningOption == VoteOption.Include) {
  //     voterAmount = voterVotesIncludeNth(_challengeIndex, _voter);
  //   } else if (winningOption == VoteOption.Exclude) {
  //     voterAmount = voterVotesExcludeNth(_challengeIndex, _voter);
  //   }
  //   return (voterAmount.mul(challenges[_challengeIndex].rewardPool)) / winningAmount;
  // }

  /**
   * @dev Returns token reward amount belonging to a challenger
   *
   * @return Amount of token
   */
  // function entryReward() public constant returns (uint) {
  //   return entryRewardNth(currentChallengeIndex());
  // }
  // function entryRewardNth(uint _challengeIndex) public constant returns (uint) {
  //   return deposit.sub(challenges[_challengeIndex].rewardPool);
  // }

  /**
   * @dev Returns all basic state related to this contract for simpler offchain access
   * For challenge info see loadChallenge()
   */
  // function loadRegistryEntry() public constant returns (uint, Status, address, uint, uint, uint) {
  //   return (
  //   version,
  //   status(),
  //   creator,
  //   deposit,
  //   challengePeriodEnd,
  //   challenges.length
  //   );
  // }

  /**
   * @dev Returns all challenge state related to this contract for simpler offchain access
   */
  // function loadChallenge(uint _challengeIndex) public constant returns (uint, address, uint, bytes, uint, uint, uint, uint, uint, uint) {
  //   Challenge storage challenge = challenges[_challengeIndex];
  //   uint include = votesIncludeNth(_challengeIndex);
  //   uint exclude = votesExcludeNth(_challengeIndex);
  //   return (
  //   challengePeriodEnd,
  //   challenge.challenger,
  //   challenge.rewardPool,
  //   challenge.metaHash,
  //   challenge.commitPeriodEnd,
  //   challenge.revealPeriodEnd,
  //   include,
  //   exclude,
  //   challenge.claimedRewardOn,
  //   challenge.voteQuorum
  //   );
  // }

  /**
   * @dev Returns all state related to vote for simpler offchain access
   *
   * @param _voter Address of a voter
   */
  // function loadVote(uint _challengeIndex, address _voter) public constant returns (bytes32, VoteOption, uint, uint, uint) {
  //   Challenge storage challenge = challenges[_challengeIndex];
  //   Vote storage vote = challenge.vote[_voter];
  //   return (
  //   vote.secretHash,
  //   vote.option,
  //   vote.amount,
  //   vote.revealedOn,
  //   vote.claimedRewardOn
  //   );
  // }
}




