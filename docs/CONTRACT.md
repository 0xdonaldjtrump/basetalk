# BaseTalk contract reference

Network: **Base mainnet** · Contract: [`0x0092fc52A827059F560FDA59b11b1DE7Bf41a056`](https://basescan.org/address/0x0092fc52A827059F560FDA59b11b1DE7Bf41a056)

## User functions
| Function | Cost | Description |
|---|---|---|
| `register(string nick)` | $1 (once) | Get the next free number forever |
| `sendMessage(uint32 to, string text)` | $0.01 | Send a message (max 300 bytes) |
| `setStatus(uint8 status, string text)` | gas | 0 invisible · 1 available · 2 away · 3 busy |
| `setNick(string nick)` | gas | Change your nickname |
| `addContact(uint32)` / `removeContact(uint32)` | gas | Manage your contact list |
| `setBlocked(uint32, bool)` | gas | Block / unblock a number |

## Read functions (free)
`getUser`, `getUsers(offset, limit)`, `getUsersBatch(ids)`, `numberOf(address)`, `getChats(number)`,
`getConversation(a, b, offset, limit)`, `conversationLength(a, b)`, `getContacts(number)`, `stats()`,
`registerFeeWei()`, `messageFeeWei()`, `weiPerUsd()`.

## Admin (owner only)
`setFees(registerMicroUsd, messageMicroUsd)`, `setPaused(bool)`, `setFallbackWeiPerUsd(value, useFixed)`,
`setPriceFeed(feed, maxAge)`, `transferOwnership(newOwner)`.

Fees are stored in micro-dollars (1 USD = 1,000,000) and converted to ETH with the Chainlink ETH/USD feed on Base.
