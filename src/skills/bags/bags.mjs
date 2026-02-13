#!/usr/bin/env node

// bags -- On-chain DEX research, trading, scanning, and autonomous trading intelligence
// V3: Persistent state, trading journal, watchlist, position sizing, goal tracking

import {
  cmdPool, cmdPump, cmdNew, cmdPrice, cmdSearch,
  cmdQuote, cmdToken, cmdSafety,
  cmdMeta, cmdHolders, cmdHistory,
  cmdWallet, cmdBuy, cmdSell, cmdPositions,
  cmdScan,
  cmdJournal, cmdWatch, cmdCalc, cmdReview,
  cmdMarket, cmdOdds, cmdBet, cmdRedeem,
} from "./lib/commands.mjs";

// ─── Help ───────────────────────────────────────────────────────────────────

function usage() {
  console.log(`
bags -- On-chain DEX Research, Trading & Autonomous Intelligence (Base + Solana)

RESEARCH:
  bags pool <chain> <address>              Pool/pair info (auto-detects DEX)
  bags pump <mintAddress>                  Pump.fun bonding curve status
  bags new <chain> [--limit N] [--dex X]   Recently created pools
  bags price <chain> <tokenAddress>        Token price (best pool + Jupiter USD)
  bags search <chain> <tokenAddress>       Find all pools for a token

JUPITER (Solana):
  bags quote sol <in> <out> <amt>          Swap quote + price impact
  bags token <query>                       Search tokens by name/symbol/address
  bags safety <mint>                       Rug/scam check via Jupiter Shield

HELIUS (Solana, requires HELIUS_API_KEY):
  bags meta sol <mint>                     Full DAS metadata
  bags holders sol <mint> [--limit N]      Top holders + concentration %
  bags history sol <addr> [--limit N]      Decoded recent transactions

TRADING (self-custody):
  bags wallet [base|sol]                   Wallet address + balance + tokens
  bags buy sol <token> <solAmt>            Buy token with SOL (auto-journals)
  bags buy base <token> <ethAmt>           Buy token with ETH via Uniswap V2
  bags sell sol <token> <amt|all>          Sell token for SOL (auto-journals)
  bags sell base <token> <amt|all>         Sell token for ETH via Uniswap V2
  bags positions [base|sol]                Current token holdings

SCANNER (Solana, requires HELIUS_API_KEY):
  bags scan sol [--limit N]                Discover & rank new tokens

JOURNAL:
  bags journal [--last N] [--status S]     Show trade journal
  bags journal add <type> <chain> <mint> <amt> <price>  Manual entry
  bags journal review [--narrative X]      Win rate, Kelly, P&L analysis

WATCHLIST:
  bags watch add <mint> [--target-buy P] [--target-sell P]  Add to watchlist
  bags watch remove <mint>                 Remove from watchlist
  bags watch list                          Watchlist + current prices
  bags watch check                         Check prices, holders, alerts

CALCULATOR:
  bags calc target <price> <supply> <$target>   Tokens needed for $X
  bags calc mcap <held> <supply> <$target>      Mcap needed for bag = $X
  bags calc size <portfolio> <risk%> <price>    Position size (+ Kelly)

PREDICTION MARKETS (Polymarket, requires POLYMARKET_PRIVATE_KEY):
  bags market search <query>            Search prediction markets
  bags market <conditionId>             Market details + order book
  bags market positions                 Your Polymarket positions
  bags market orders                    Open limit orders
  bags market cancel <orderId|all>      Cancel order(s)
  bags market trades [--last N]         Trade history
  bags odds <conditionId>               Current YES/NO prices + spread
  bags bet <id> <yes|no> <$amt>         Market order (instant fill)
  bags bet <id> <yes|no> <$amt> --limit 0.65  Limit order
  bags redeem <conditionId>             Check/redeem resolved position
  bags redeem list                      Redeemable positions

REVIEW:
  bags review                              Full portfolio + goal progress + alerts

META:
  bags help                                Show this help

Chains: base, sol (or solana)

Supported DEXes:
  Base:    Uniswap V2, Aerodrome
  Solana:  Raydium AMM v4, Pump.fun, PumpSwap, Meteora DLMM, Meteora CP-AMM

Environment variables:
  SOLANA_PRIVATE_KEY      Self-custody wallet key (base58 or JSON byte array)
  BASE_PRIVATE_KEY        EVM wallet key for Base trading (hex, 0x prefix optional)
  POLYMARKET_PRIVATE_KEY  Polygon wallet key for Polymarket (hex, 0x prefix)
  HELIUS_API_KEY          Enhanced Solana RPC + DAS + holders + scanner
  JUPITER_API_KEY         Optional, improves Jupiter rate limits
  BASE_RPC_URL            Custom Base RPC (default: mainnet.base.org)
  SOLANA_RPC_URL          Custom Solana RPC (auto-upgraded by Helius)
  BAGS_STATE_DIR          Custom state directory (default: /data/.bags or ~/.bags)

All output is JSON.
`.trim());
}

// ─── Dispatch ───────────────────────────────────────────────────────────────

const COMMANDS = {
  pool: cmdPool,
  pump: cmdPump,
  new: cmdNew,
  price: cmdPrice,
  search: cmdSearch,
  quote: cmdQuote,
  token: cmdToken,
  safety: cmdSafety,
  meta: cmdMeta,
  holders: cmdHolders,
  history: cmdHistory,
  wallet: cmdWallet,
  buy: cmdBuy,
  sell: cmdSell,
  positions: cmdPositions,
  scan: cmdScan,
  journal: cmdJournal,
  watch: cmdWatch,
  calc: cmdCalc,
  review: cmdReview,
  market: cmdMarket,
  odds: cmdOdds,
  bet: cmdBet,
  redeem: cmdRedeem,
};

async function main() {
  const [command, ...args] = process.argv.slice(2);

  if (!command || command === "help" || command === "--help" || command === "-h") {
    usage();
    process.exit(0);
  }

  try {
    const fn = COMMANDS[command];
    if (!fn) {
      console.error(`Unknown command: ${command}`);
      usage();
      process.exit(1);
    }
    await fn(args);
  } catch (err) {
    console.error(JSON.stringify({
      error: true,
      message: err.message,
      stack: err.stack?.split("\n").slice(0, 3),
    }, null, 2));
    process.exit(1);
  }
}

main();
