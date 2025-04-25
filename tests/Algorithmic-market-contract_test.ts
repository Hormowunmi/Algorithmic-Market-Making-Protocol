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
     
     // Register a token
     let block = chain.mineBlock([
       Tx.contractCall(
         'algorithmic-market-maker', 
         'register-token', 
         [
           types.ascii("STX"),                        // token-id
           types.ascii("Stacks Token"),               // name
           types.ascii("fungible"),                   // token-type
           types.principal(deployer.address),         // contract
           types.uint(6),                             // decimals
           types.principal(oracle.address),           // price-oracle
           types.bool(false),                         // is-stable
           types.uint(100000000000)                   // max-supply
         ], 
         deployer.address
       )
     ]);
     
     // Check token registration succeeds
     assertEquals(block.receipts[0].result, '(ok "STX")');
     
     // Try registering the same token again (should fail)
     block = chain.mineBlock([
       Tx.contractCall(
         'algorithmic-market-maker', 
         'register-token', 
         [
           types.ascii("STX"),                        // token-id
           types.ascii("Stacks Token"),               // name
           types.ascii("fungible"),                   // token-type
           types.principal(deployer.address),         // contract
           types.uint(6),                             // decimals
           types.principal(oracle.address),           // price-oracle
           types.bool(false),                         // is-stable
           types.uint(100000000000)                   // max-supply
         ], 
         deployer.address
       )
     ]);
     
     // Check it fails with err-token-exists
     assertEquals(getErrCode(block.receipts[0]), 104);
   },
 });
 
 Clarinet.test({
   name: "Pool creation works correctly",
   async fn(chain: Chain, accounts: Map<string, Account>) {
     const deployer = accounts.get('deployer')!;
     const treasury = accounts.get('wallet_1')!;
     const oracle = accounts.get('wallet_2')!;
     
     // Setup: Initialize protocol and register tokens
     chain.mineBlock([
       Tx.contractCall(
         'algorithmic-market-maker', 
         'initialize', 
         [types.principal(treasury.address)], 
         deployer.address
       ),
       
       // Register first token (STX)
       Tx.contractCall(
         'algorithmic-market-maker', 
         'register-token', 
         [
           types.ascii("STX"),                        // token-id
           types.ascii("Stacks Token"),               // name
           types.ascii("fungible"),                   // token-type
           types.principal(deployer.address),         // contract
           types.uint(6),                             // decimals
           types.principal(oracle.address),           // price-oracle
           types.bool(false),                         // is-stable
           types.uint(100000000000)                   // max-supply
         ], 
         deployer.address
       ),
       
       // Register second token (USDA)
       Tx.contractCall(
         'algorithmic-market-maker', 
         'register-token', 
         [
           types.ascii("USDA"),                       // token-id
           types.ascii("USDA Stablecoin"),            // name
           types.ascii("fungible"),                   // token-type
           types.principal(deployer.address),         // contract
           types.uint(6),                             // decimals
           types.principal(oracle.address),           // price-oracle
           types.bool(true),                          // is-stable
           types.uint(1000000000)                     // max-supply
         ], 
         deployer.address
       )
     ]);
     
     // Create a new pool
     let block = chain.mineBlock([
       Tx.contractCall(
         'algorithmic-market-maker', 
         'create-pool', 
         [
           types.ascii("STX"),                        // token-x
           types.ascii("USDA"),                       // token-y
           types.uint(0),                             // curve-type (Constant Product)
           types.list([types.uint(0), types.uint(0), types.uint(0), types.uint(0), types.uint(0)]), // curve-params
           types.uint(30),                            // base-fee-bp (0.3%)
           types.uint(1)                              // tick-spacing
         ], 
         deployer.address
       )
     ]);
     
     // Check pool creation succeeds
     const result = block.receipts[0].result;
     const expectedPartial = '(ok (pool-id u1))';
     assertEquals(result.includes(expectedPartial), true);
     
     // Test non-owner cannot create pool
     const nonOwner = accounts.get('wallet_3')!;
     block = chain.mineBlock([
       Tx.contractCall(
         'algorithmic-market-maker', 
         'create-pool', 
         [
           types.ascii("STX"),                        // token-x
           types.ascii("USDA"),                       // token-y
           types.uint(0),                             // curve-type (Constant Product)
           types.list([types.uint(0), types.uint(0), types.uint(0), types.uint(0), types.uint(0)]), // curve-params
           types.uint(30),                            // base-fee-bp (0.3%)
           types.uint(1)                              // tick-spacing
         ], 
         nonOwner.address
       )
     ]);
     
     // Check it fails with err-owner-only
     assertEquals(getErrCode(block.receipts[0]), 100);
   },
 });
 
 // Mock for the token transfer function - in real testing you'd implement actual token transfers
 function mockTransferToken(
   chain: Chain, 
   token: string, 
   amount: number, 
   sender: Account, 
   recipient: string
 ): void {
   // In a real implementation, this would interact with the token contract
   // For testing purposes, we just assume it works
 }
 
 Clarinet.test({
   name: "Adding standard liquidity works correctly",
   async fn(chain: Chain, accounts: Map<string, Account>) {
     const deployer = accounts.get('deployer')!;
     const treasury = accounts.get('wallet_1')!;
     const oracle = accounts.get('wallet_2')!;
     const liquidityProvider = accounts.get('wallet_3')!;
     
     // Setup: Initialize protocol, register tokens, create pool
     chain.mineBlock([
       // Initialize
       Tx.contractCall(
         'algorithmic-market-maker', 
         'initialize', 
         [types.principal(treasury.address)], 
         deployer.address
       ),
       
       // Register tokens
       Tx.contractCall(
         'algorithmic-market-maker', 
         'register-token', 
         [
           types.ascii("STX"),                        // token-id
           types.ascii("Stacks Token"),               // name
           types.ascii("fungible"),                   // token-type
           types.principal(deployer.address),         // contract
           types.uint(6),                             // decimals
           types.principal(oracle.address),           // price-oracle
           types.bool(false),                         // is-stable
           types.uint(100000000000)                   // max-supply
         ], 
         deployer.address
       ),