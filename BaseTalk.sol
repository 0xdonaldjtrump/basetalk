// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    BaseTalk — on-chain messenger on Base, in the spirit of classic numbered IM apps.

    Fees (priced in USD, paid in ETH using the Chainlink ETH/USD feed):
      - one-time registration: $1.00  -> you get your own number (#1, #2, #3 ...) forever
      - every sent message:    $0.01
    Fees are stored in micro-dollars (1 USD = 1_000_000), so the owner can set
    anything down to $0.000001 (e.g. 100 = $0.0001 = 0.01 cent).
      - reading, contacts, status, profile: free (gas only)

    All fees go straight to the owner wallet (the wallet that deployed this contract).
    Note: messages are stored on a public blockchain — anyone can read them on a block explorer.
*/

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract BaseTalk {
    // ---------- types ----------
    struct Msg {
        uint32 from;  // sender number
        uint32 to;    // recipient number
        uint64 time;  // block timestamp
        string text;
    }

    struct User {
        address wallet;
        uint32 number;
        uint8 status;      // 0 = offline/invisible, 1 = available, 2 = away, 3 = busy
        uint64 joined;
        uint64 lastActive;
        string nick;
        string statusText; // short description shown next to the nick
    }

    // ---------- config ----------
    address public owner;
    AggregatorV3Interface public priceFeed;
    uint256 public registerFeeMicroUsd = 1_000_000; // $1.00
    uint256 public messageFeeMicroUsd = 10_000;     // $0.01
    uint256 public fallbackWeiPerUsd = 333333333333333; // 1 USD at ETH=$3000, used only if the oracle is down/stale
    uint256 public maxPriceAge = 6 hours;
    uint8 public feedDecimals = 8;
    bool public useFixedPrice; // owner switch: ignore oracle, use fallbackWeiPerUsd
    bool public paused;

    uint256 public constant MAX_TEXT = 300;
    uint256 public constant MAX_NICK = 24;
    uint256 public constant MAX_STATUS_TEXT = 70;

    // ---------- storage ----------
    uint32 public userCount;              // last assigned number
    mapping(address => uint32) public numberOf;
    mapping(uint32 => User) private users;

    Msg[] private messages;
    mapping(bytes32 => uint256[]) private convo;        // pair key -> message ids
    mapping(uint32 => uint32[]) private partners;        // who I talked with
    mapping(bytes32 => bool) private partnerKnown;
    mapping(uint32 => uint256) public inboxCount;        // messages received
    mapping(uint32 => uint32[]) private contacts;        // manual contact list
    mapping(uint32 => mapping(uint32 => uint256)) private contactIndex; // index+1
    mapping(uint32 => mapping(uint32 => bool)) public blocked; // blocked[me][them]

    uint256 public totalFeesMicroUsd;

    // ---------- events ----------
    event Registered(uint32 indexed number, address indexed wallet, string nick);
    event MessageSent(uint256 indexed id, uint32 indexed from, uint32 indexed to, string text);
    event StatusChanged(uint32 indexed number, uint8 status, string statusText);
    event NickChanged(uint32 indexed number, string nick);
    event ContactAdded(uint32 indexed number, uint32 indexed contact);
    event ContactRemoved(uint32 indexed number, uint32 indexed contact);
    event Blocked(uint32 indexed number, uint32 indexed other, bool isBlocked);
    event FeesChanged(uint256 registerFeeMicroUsd, uint256 messageFeeMicroUsd);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    // ---------- errors ----------
    error NotOwner();
    error Paused();
    error AlreadyRegistered();
    error NotRegistered();
    error UnknownNumber();
    error FeeTooLow(uint256 required, uint256 sent);
    error BadLength();
    error SelfAction();
    error YouAreBlocked();
    error TransferFailed();
    error BadStatus();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier notPaused() {
        if (paused) revert Paused();
        _;
    }

    constructor() {
        owner = msg.sender;
        // Chainlink ETH/USD on Base mainnet
        priceFeed = AggregatorV3Interface(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);
    }

    // =====================================================================
    //                              PRICING
    // =====================================================================

    /// @notice How much wei equals 1 USD right now (oracle, or fallback if oracle is down/stale).
    function weiPerUsd() public view returns (uint256) {
        if (useFixedPrice || address(priceFeed).code.length == 0) return fallbackWeiPerUsd;
        try priceFeed.latestRoundData() returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80) {
            if (answer <= 0 || updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > maxPriceAge) {
                return fallbackWeiPerUsd;
            }
            return (1e18 * (10 ** uint256(feedDecimals))) / uint256(answer);
        } catch {
            return fallbackWeiPerUsd;
        }
    }

    function quoteMicroUsd(uint256 microUsd) public view returns (uint256) {
        return (weiPerUsd() * microUsd) / 1_000_000;
    }

    function registerFeeWei() external view returns (uint256) {
        return quoteMicroUsd(registerFeeMicroUsd);
    }

    function messageFeeWei() external view returns (uint256) {
        return quoteMicroUsd(messageFeeMicroUsd);
    }

    function _takeFee(uint256 microUsd) private {
        uint256 required = quoteMicroUsd(microUsd);
        if (msg.value < required) revert FeeTooLow(required, msg.value);
        totalFeesMicroUsd += microUsd;
        if (msg.value > 0) {
            (bool ok, ) = owner.call{value: msg.value}("");
            if (!ok) revert TransferFailed();
        }
    }

    // =====================================================================
    //                            USER ACTIONS
    // =====================================================================

    /// @notice One-time payment of $1 — you get your number forever.
    function register(string calldata nick) external payable notPaused returns (uint32 number) {
        if (numberOf[msg.sender] != 0) revert AlreadyRegistered();
        uint256 len = bytes(nick).length;
        if (len == 0 || len > MAX_NICK) revert BadLength();

        _takeFee(registerFeeMicroUsd);

        number = ++userCount;
        numberOf[msg.sender] = number;
        User storage u = users[number];
        u.wallet = msg.sender;
        u.number = number;
        u.status = 1;
        u.joined = uint64(block.timestamp);
        u.lastActive = uint64(block.timestamp);
        u.nick = nick;

        emit Registered(number, msg.sender, nick);
    }

    /// @notice Send a message to another user's number — $0.01.
    function sendMessage(uint32 to, string calldata text) external payable notPaused returns (uint256 id) {
        uint32 from = _me();
        if (to == 0 || to > userCount) revert UnknownNumber();
        if (to == from) revert SelfAction();
        uint256 len = bytes(text).length;
        if (len == 0 || len > MAX_TEXT) revert BadLength();
        if (blocked[to][from]) revert YouAreBlocked();

        _takeFee(messageFeeMicroUsd);

        id = messages.length;
        messages.push(Msg({from: from, to: to, time: uint64(block.timestamp), text: text}));

        bytes32 key = _pairKey(from, to);
        convo[key].push(id);
        if (!partnerKnown[key]) {
            partnerKnown[key] = true;
            partners[from].push(to);
            partners[to].push(from);
        }
        inboxCount[to] += 1;
        users[from].lastActive = uint64(block.timestamp);

        emit MessageSent(id, from, to, text);
    }

    function setStatus(uint8 status, string calldata statusText) external {
        uint32 me = _me();
        if (status > 3) revert BadStatus();
        if (bytes(statusText).length > MAX_STATUS_TEXT) revert BadLength();
        users[me].status = status;
        users[me].statusText = statusText;
        users[me].lastActive = uint64(block.timestamp);
        emit StatusChanged(me, status, statusText);
    }

    function setNick(string calldata nick) external {
        uint32 me = _me();
        uint256 len = bytes(nick).length;
        if (len == 0 || len > MAX_NICK) revert BadLength();
        users[me].nick = nick;
        emit NickChanged(me, nick);
    }

    function addContact(uint32 who) external {
        uint32 me = _me();
        if (who == 0 || who > userCount) revert UnknownNumber();
        if (who == me) revert SelfAction();
        if (contactIndex[me][who] != 0) return;
        contacts[me].push(who);
        contactIndex[me][who] = contacts[me].length;
        emit ContactAdded(me, who);
    }

    function removeContact(uint32 who) external {
        uint32 me = _me();
        uint256 idx = contactIndex[me][who];
        if (idx == 0) return;
        uint32[] storage list = contacts[me];
        uint32 last = list[list.length - 1];
        list[idx - 1] = last;
        contactIndex[me][last] = idx;
        list.pop();
        contactIndex[me][who] = 0;
        emit ContactRemoved(me, who);
    }

    function setBlocked(uint32 who, bool isBlocked) external {
        uint32 me = _me();
        if (who == 0 || who > userCount) revert UnknownNumber();
        if (who == me) revert SelfAction();
        blocked[me][who] = isBlocked;
        emit Blocked(me, who, isBlocked);
    }

    // =====================================================================
    //                               READS
    // =====================================================================

    function getUser(uint32 number) public view returns (User memory) {
        if (number == 0 || number > userCount) revert UnknownNumber();
        return users[number];
    }

    function getUserByWallet(address wallet) external view returns (User memory u) {
        uint32 n = numberOf[wallet];
        if (n != 0) u = users[n];
    }

    /// @notice Public directory, page by page (numbers start..start+count-1).
    function getUsers(uint32 start, uint32 count) external view returns (User[] memory list) {
        if (start == 0) start = 1;
        if (start > userCount) return new User[](0);
        uint32 end = start + count - 1;
        if (end > userCount || end < start) end = userCount;
        list = new User[](end - start + 1);
        for (uint32 i = start; i <= end; i++) list[i - start] = users[i];
    }

    function getUsersBatch(uint32[] calldata numbers) external view returns (User[] memory list) {
        list = new User[](numbers.length);
        for (uint256 i; i < numbers.length; i++) {
            uint32 n = numbers[i];
            if (n != 0 && n <= userCount) list[i] = users[n];
        }
    }

    function getContacts(uint32 number) external view returns (uint32[] memory) {
        return contacts[number];
    }

    function getPartners(uint32 number) external view returns (uint32[] memory) {
        return partners[number];
    }

    /// @notice Chat list for a user in one call: partners, message count per conversation, time of last message.
    function getChats(uint32 number)
        external
        view
        returns (uint32[] memory ids, uint256[] memory counts, uint64[] memory lastTimes)
    {
        uint32[] storage p = partners[number];
        uint256 n = p.length;
        ids = new uint32[](n);
        counts = new uint256[](n);
        lastTimes = new uint64[](n);
        for (uint256 i; i < n; i++) {
            uint256[] storage c = convo[_pairKey(number, p[i])];
            ids[i] = p[i];
            counts[i] = c.length;
            if (c.length > 0) lastTimes[i] = messages[c[c.length - 1]].time;
        }
    }

    function conversationLength(uint32 a, uint32 b) external view returns (uint256) {
        return convo[_pairKey(a, b)].length;
    }

    /// @notice Messages between a and b. offset/limit count from the oldest message.
    function getConversation(uint32 a, uint32 b, uint256 offset, uint256 limit)
        external
        view
        returns (Msg[] memory list, uint256[] memory ids)
    {
        uint256[] storage all = convo[_pairKey(a, b)];
        uint256 n = all.length;
        if (offset >= n) return (new Msg[](0), new uint256[](0));
        uint256 end = offset + limit;
        if (end > n) end = n;
        list = new Msg[](end - offset);
        ids = new uint256[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            ids[i - offset] = all[i];
            list[i - offset] = messages[all[i]];
        }
    }

    function totalMessages() external view returns (uint256) {
        return messages.length;
    }

    function stats()
        external
        view
        returns (uint32 users_, uint256 messages_, uint256 feesMicroUsd_, uint256 regFeeWei_, uint256 msgFeeWei_)
    {
        return (userCount, messages.length, totalFeesMicroUsd, quoteMicroUsd(registerFeeMicroUsd), quoteMicroUsd(messageFeeMicroUsd));
    }

    // =====================================================================
    //                               ADMIN
    // =====================================================================

    function setFees(uint256 _registerFeeMicroUsd, uint256 _messageFeeMicroUsd) external onlyOwner {
        registerFeeMicroUsd = _registerFeeMicroUsd;
        messageFeeMicroUsd = _messageFeeMicroUsd;
        emit FeesChanged(_registerFeeMicroUsd, _messageFeeMicroUsd);
    }

    function setPriceFeed(address feed, uint8 _decimals, uint256 _maxPriceAge) external onlyOwner {
        priceFeed = AggregatorV3Interface(feed);
        feedDecimals = _decimals;
        maxPriceAge = _maxPriceAge;
    }

    function setFallbackWeiPerUsd(uint256 value, bool _useFixedPrice) external onlyOwner {
        require(value > 0, "zero");
        fallbackWeiPerUsd = value;
        useFixedPrice = _useFixedPrice;
    }

    function setPaused(bool value) external onlyOwner {
        paused = value;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    /// @notice In case anyone sends ETH directly — sweep to owner.
    function withdraw() external onlyOwner {
        (bool ok, ) = owner.call{value: address(this).balance}("");
        if (!ok) revert TransferFailed();
    }

    receive() external payable {}

    // ---------- internal ----------
    function _me() private view returns (uint32 n) {
        n = numberOf[msg.sender];
        if (n == 0) revert NotRegistered();
    }

    function _pairKey(uint32 a, uint32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
