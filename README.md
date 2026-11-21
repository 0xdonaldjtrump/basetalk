# BaseTalk

A classic numbered messenger living on the **Base** blockchain.

- **$1 once** — you get your own number (#1, #2, #3 …) forever
- **$0.01 per sent message** (admin can change fees, down to $0.000001)
- Reading, contacts, status, directory — free (gas only)
- Fees are priced in USD and paid in ETH (Chainlink ETH/USD oracle with a backup price)
- All fees go straight to the contract owner's wallet

`index.html` is the whole app (static, works on GitHub Pages). `BaseTalk.sol` is the smart contract.

> Messages are stored on a public blockchain — anyone can read them on a block explorer.
