# How BaseTalk works

1. **Numbers** – the first wallet to register gets `#1`, the next `#2`, and so on. A number belongs to the wallet forever.
2. **Fees in USD, paid in ETH** – the contract reads the Chainlink ETH/USD price on Base and converts the $1 / $0.01 fees to wei.
   If the oracle is down or stale, a backup price set by the owner is used (no reverts, the app keeps working).
3. **Fees go straight to the owner** – every payment is forwarded in the same transaction; the contract never holds user funds.
4. **Messages are public** – they are stored on-chain. Anyone can read them with a block explorer. Do not send secrets.
5. **No backend** – `index.html` talks directly to Base through public RPC endpoints (reads) and your wallet (writes).
   New messages are found by polling `getChats` every few seconds.
6. **Wallets** – EIP-6963 discovery, so MetaMask, Coinbase Wallet, Rabby etc. all work, even when several are installed.
