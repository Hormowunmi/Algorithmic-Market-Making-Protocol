import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v0.14.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

// Helper to get error codes from receipts
function getErrCode(receipt: any): number {
  if (receipt.result.startsWith('(err ')) {
    const errValue = receipt.result.substring(5, receipt.result.length - 1);
    return parseInt(errValue.substring(1));
  }
  return -1;
}

Clarinet.test({
  name: "Ensure protocol can be initialized",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const treasury = accounts.get('wallet_1')!;
    
    // Initialize protocol
    let block = chain.mineBlock([
      Tx.contractCall(
        'algorithmic-market-maker', 
        'initialize', 
        [types.principal(treasury.address)], 
        deployer.address
      )
    ]);
    
    // Check initialization succeeds
    assertEquals(block.receipts[0].result, '(ok true)');
    assertEquals(block.height, 2);
  },
});

Clarinet.test({
  name: "Only contract owner can initialize protocol",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const nonOwner = accounts.get('wallet_1')!;
    const treasury = accounts.get('wallet_2')!;
    
    // Non-owner attempts to initialize
    let block = chain.mineBlock([
      Tx.contractCall(
        'algorithmic-market-maker', 
        'initialize', 
        [types.principal(treasury.address)], 
        nonOwner.address
      )
    ]);
    
    // Check it fails with err-owner-only
    assertEquals(getErrCode(block.receipts[0]), 100);
  },
});

Clarinet.test({
  name: "Token registration works correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const treasury = accounts.get('wallet_1')!;
    const oracle = accounts.get('wallet_2')!;
    
    // Initialize protocol first
    chain.mineBlock([
      Tx.contractCall(
        'algorithmic-market-maker', 
        'initialize', 
        [types.principal(treasury.address)], 
        deployer.address
      )
    ]);
    