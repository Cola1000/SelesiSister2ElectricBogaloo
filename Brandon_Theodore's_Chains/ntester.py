#!/usr/bin/env python3
"""
Interactive Bitcoin Network Tester
Test and interact with your mini Bitcoin network
"""

import requests
import json
import time
import random
from typing import List, Dict, Any
import argparse

class NetworkTester:
    def __init__(self, ports: List[int]):
        self.ports = ports
        self.nodes = [f"http://localhost:{port}" for port in ports]
        self.session = requests.Session()
        self.session.timeout = 10
    
    def print_banner(self):
        print("=" * 60)
        print("🚀 Mini Bitcoin Network Tester")
        print("=" * 60)
        print(f"Connected to {len(self.nodes)} nodes:")
        for i, node in enumerate(self.nodes):
            print(f"  Node {i+1}: {node}")
        print()
    
    def get_node_status(self, node_url: str) -> Dict[str, Any]:
        """Get status of a single node"""
        try:
            response = self.session.get(f"{node_url}/health")
            response.raise_for_status()
            return response.json()
        except Exception as e:
            return {"error": str(e)}
    
    def check_all_nodes(self):
        """Check status of all nodes"""
        print("🔍 Checking node status...")
        print("-" * 40)
        
        all_healthy = True
        for i, node in enumerate(self.nodes):
            status = self.get_node_status(node)
            
            if "error" in status:
                print(f"❌ Node {i+1} ({node}): ERROR - {status['error']}")
                all_healthy = False
            else:
                print(f"✅ Node {i+1} ({node}):")
                print(f"   - Height: {status.get('height', 'N/A')}")
                print(f"   - Difficulty: {status.get('difficulty', 'N/A')}")
                print(f"   - Peers: {status.get('peers', 'N/A')}")
                print(f"   - Mempool: {status.get('mempool_size', 'N/A')} txs")
        
        print()
        return all_healthy
    
    def add_random_transaction(self) -> bool:
        """Add a random transaction to a random node"""
        names = ["Alice", "Bob", "Charlie", "Dave", "Eve", "Frank", "Grace", "Henry"]
        sender = random.choice(names)
        recipient = random.choice([n for n in names if n != sender])
        amount = round(random.uniform(0.1, 100.0), 2)
        
        transaction = {
            "sender": sender,
            "recipient": recipient,
            "amount": amount
        }
        
        node = random.choice(self.nodes)
        
        try:
            response = self.session.post(f"{node}/transaction", json=transaction)
            response.raise_for_status()
            
            print(f"💸 Added transaction: {sender} → {recipient} ({amount} BTC)")
            print(f"   Submitted to: {node}")
            return True
        except Exception as e:
            print(f"❌ Failed to add transaction: {e}")
            return False
    
    def mine_block(self, node_index: int = 0, miner: str = "TestMiner", reward: float = 12.5) -> bool:
        """Mine a block on specified node"""
        if node_index >= len(self.nodes):
            print(f"❌ Invalid node index: {node_index}")
            return False
        
        node = self.nodes[node_index]
        
        print(f"⛏️  Mining block on Node {node_index + 1}...")
        print(f"   Miner: {miner}")
        print(f"   Reward: {reward} BTC")
        
        try:
            start_time = time.time()
            response = self.session.get(f"{node}/mine", 
                                      params={"miner": miner, "reward": reward})
            response.raise_for_status()
            mining_time = time.time() - start_time
            
            result = response.json()
            
            print(f"✅ Block mined successfully!")
            print(f"   Mining time: {result.get('mining_time', mining_time):.2f}s")
            print(f"   Block index: {result['block']['index']}")
            print(f"   Nonce: {result['block']['nonce']}")
            print(f"   Hash: {result['block']['hash'][:16]}...")
            print(f"   Broadcasted to: {result.get('broadcasted_to', 0)} peers")
            return True
        except Exception as e:
            print(f"❌ Mining failed: {e}")
            return False
    
    def get_chain_info(self, node_index: int = 0) -> Dict[str, Any]:
        """Get blockchain info from specified node"""
        if node_index >= len(self.nodes):
            return {"error": f"Invalid node index: {node_index}"}
        
        node = self.nodes[node_index]
        
        try:
            response = self.session.get(f"{node}/chain")
            response.raise_for_status()
            return response.json()
        except Exception as e:
            return {"error": str(e)}
    
    def show_chain_summary(self):
        """Show blockchain summary for all nodes"""
        print("⛓️  Blockchain Summary")
        print("-" * 40)
        
        for i, node in enumerate(self.nodes):
            chain_info = self.get_chain_info(i)
            
            if "error" in chain_info:
                print(f"❌ Node {i+1}: ERROR - {chain_info['error']}")
            else:
                length = chain_info["length"]
                print(f"📊 Node {i+1}: {length} blocks")
                
                # Show last few blocks
                if length > 1:
                    last_block = chain_info["chain"][-1]
                    print(f"   Last block: #{last_block['index']}")
                    print(f"   Hash: {last_block['hash'][:16]}...")
                    print(f"   Transactions: {len(last_block['transactions'])}")
        print()
    
    def show_detailed_block(self, node_index: int = 0, block_index: int = -1):
        """Show detailed information about a specific block"""
        chain_info = self.get_chain_info(node_index)
        
        if "error" in chain_info:
            print(f"❌ Error getting chain: {chain_info['error']}")
            return
        
        chain = chain_info["chain"]
        
        if block_index == -1:
            block_index = len(chain) - 1
        
        if block_index < 0 or block_index >= len(chain):
            print(f"❌ Invalid block index: {block_index}")
            return
        
        block = chain[block_index]
        
        print(f"🔍 Block #{block['index']} Details")
        print("-" * 40)
        print(f"Hash: {block['hash']}")
        print(f"Previous Hash: {block['previous_hash']}")
        print(f"Merkle Root: {block['merkle_root']}")
        print(f"Timestamp: {time.ctime(block['timestamp'])}")
        print(f"Nonce: {block['nonce']}")
        print(f"Difficulty: {block['difficulty']}")
        print(f"Transactions ({len(block['transactions'])}):")
        
        for i, tx in enumerate(block['transactions']):
            print(f"  {i+1}. {tx['sender']} → {tx['recipient']}: {tx['amount']} BTC")
        
        print()
    
    def show_mempool(self, node_index: int = 0):
        """Show transaction pool of specified node"""
        if node_index >= len(self.nodes):
            print(f"❌ Invalid node index: {node_index}")
            return
        
        node = self.nodes[node_index]
        
        try:
            response = self.session.get(f"{node}/transactions/pool")
            response.raise_for_status()
            pool_info = response.json()
            
            print(f"💰 Node {node_index + 1} Transaction Pool")
            print("-" * 40)
            print(f"Total transactions: {pool_info['count']}")
            
            for i, tx in enumerate(pool_info['transactions']):
                print(f"  {i+1}. {tx['sender']} → {tx['recipient']}: {tx['amount']} BTC")
            
            print()
        except Exception as e:
            print(f"❌ Error getting mempool: {e}")
    
    def stress_test(self, num_transactions: int = 10, num_blocks: int = 3):
        """Run stress test with multiple transactions and blocks"""
        print(f"🔥 Starting stress test...")
        print(f"   Transactions: {num_transactions}")
        print(f"   Blocks to mine: {num_blocks}")
        print("-" * 40)
        
        # Add multiple transactions
        print("Adding transactions...")
        successful_txs = 0
        for i in range(num_transactions):
            if self.add_random_transaction():
                successful_txs += 1
            time.sleep(0.1)  # Small delay
        
        print(f"✅ Added {successful_txs}/{num_transactions} transactions")
        print()
        
        # Mine multiple blocks on different nodes
        print("Mining blocks...")
        successful_blocks = 0
        for i in range(num_blocks):
            node_index = i % len(self.nodes)
            miner = f"StressMiner{i+1}"
            
            if self.mine_block(node_index, miner, 10.0 + i):
                successful_blocks += 1
            
            # Wait for synchronization
            time.sleep(2)
        
        print(f"✅ Mined {successful_blocks}/{num_blocks} blocks")
        print()
        
        # Check final state
        print("Final network state:")
        time.sleep(3)  # Wait for full sync
        self.show_chain_summary()
        
        return successful_txs, successful_blocks
    
    def interactive_menu(self):
        """Interactive menu for testing"""
        while True:
            print("\n" + "="*50)
            print("🚀 Bitcoin Network Tester - Interactive Mode")
            print("="*50)
            print("1. Check all nodes status")
            print("2. Add random transaction")
            print("3. Mine block")
            print("4. Show blockchain summary")
            print("5. Show detailed block")
            print("6. Show mempool")
            print("7. Run stress test")
            print("8. Custom transaction")
            print("9. Resolve conflicts")
            print("0. Exit")
            print()
            
            try:
                choice = input("Choose option (0-9): ").strip()
                
                if choice == "0":
                    print("👋 Goodbye!")
                    break
                elif choice == "1":
                    self.check_all_nodes()
                elif choice == "2":
                    self.add_random_transaction()
                elif choice == "3":
                    self.mine_menu()
                elif choice == "4":
                    self.show_chain_summary()
                elif choice == "5":
                    self.block_details_menu()
                elif choice == "6":
                    self.mempool_menu()
                elif choice == "7":
                    self.stress_test_menu()
                elif choice == "8":
                    self.custom_transaction_menu()
                elif choice == "9":
                    self.resolve_conflicts_menu()
                else:
                    print("❌ Invalid option. Please try again.")
                
                input("\nPress Enter to continue...")
                
            except KeyboardInterrupt:
                print("\n👋 Goodbye!")
                break
            except Exception as e:
                print(f"❌ Error: {e}")
    
    def mine_menu(self):
        """Mining submenu"""
        print("\n⛏️  Mining Menu")
        print("-" * 30)
        
        for i, node in enumerate(self.nodes):
            print(f"  {i+1}. Mine on Node {i+1} ({node})")
        
        try:
            node_choice = int(input(f"Choose node (1-{len(self.nodes)}): ")) - 1
            if node_choice < 0 or node_choice >= len(self.nodes):
                print("❌ Invalid node selection")
                return
            
            miner = input("Enter miner name (default: TestMiner): ").strip() or "TestMiner"
            reward_str = input("Enter reward (default: 12.5): ").strip()
            reward = float(reward_str) if reward_str else 12.5
            
            self.mine_block(node_choice, miner, reward)
        except ValueError:
            print("❌ Invalid input")
        except Exception as e:
            print(f"❌ Error: {e}")
    
    def block_details_menu(self):
        """Block details submenu"""
        print("\n🔍 Block Details Menu")
        print("-" * 30)
        
        try:
            node_choice = int(input(f"Choose node (1-{len(self.nodes)}): ")) - 1
            if node_choice < 0 or node_choice >= len(self.nodes):
                print("❌ Invalid node selection")
                return
            
            block_str = input("Enter block index (default: latest): ").strip()
            block_index = int(block_str) if block_str else -1
            
            self.show_detailed_block(node_choice, block_index)
        except ValueError:
            print("❌ Invalid input")
        except Exception as e:
            print(f"❌ Error: {e}")
    
    def mempool_menu(self):
        """Mempool submenu"""
        print("\n💰 Mempool Menu")
        print("-" * 30)
        
        try:
            node_choice = int(input(f"Choose node (1-{len(self.nodes)}): ")) - 1
            if node_choice < 0 or node_choice >= len(self.nodes):
                print("❌ Invalid node selection")
                return
            
            self.show_mempool(node_choice)
        except ValueError:
            print("❌ Invalid input")
        except Exception as e:
            print(f"❌ Error: {e}")
    
    def stress_test_menu(self):
        """Stress test submenu"""
        print("\n🔥 Stress Test Menu")
        print("-" * 30)
        
        try:
            num_txs = int(input("Number of transactions (default: 10): ") or "10")
            num_blocks = int(input("Number of blocks to mine (default: 3): ") or "3")
            
            self.stress_test(num_txs, num_blocks)
        except ValueError:
            print("❌ Invalid input")
        except Exception as e:
            print(f"❌ Error: {e}")
    
    def custom_transaction_menu(self):
        """Custom transaction submenu"""
        print("\n💸 Custom Transaction Menu")
        print("-" * 30)
        
        try:
            sender = input("Enter sender name: ").strip()
            recipient = input("Enter recipient name: ").strip()
            amount = float(input("Enter amount: ").strip())
            
            if not sender or not recipient or amount <= 0:
                print("❌ Invalid transaction details")
                return
            
            transaction = {
                "sender": sender,
                "recipient": recipient,
                "amount": amount
            }
            
            node = random.choice(self.nodes)
            response = self.session.post(f"{node}/transaction", json=transaction)
            response.raise_for_status()
            
            print(f"✅ Transaction added: {sender} → {recipient} ({amount} BTC)")
            print(f"   Submitted to: {node}")
        except ValueError:
            print("❌ Invalid input")
        except Exception as e:
            print(f"❌ Error: {e}")
    
    def resolve_conflicts_menu(self):
        """Conflict resolution submenu"""
        print("\n🔄 Conflict Resolution Menu")
        print("-" * 30)
        
        try:
            node_choice = int(input(f"Choose node (1-{len(self.nodes)}): ")) - 1
            if node_choice < 0 or node_choice >= len(self.nodes):
                print("❌ Invalid node selection")
                return
            
            node = self.nodes[node_choice]
            response = self.session.get(f"{node}/resolve")
            response.raise_for_status()
            result = response.json()
            
            print(f"🔄 Conflict resolution result:")
            print(f"   Chain replaced: {result['replaced']}")
            print(f"   Current length: {result['length']}")
        except ValueError:
            print("❌ Invalid input")
        except Exception as e:
            print(f"❌ Error: {e}")

def main():
    parser = argparse.ArgumentParser(description="Bitcoin Network Tester")
    parser.add_argument("--ports", nargs="+", type=int, default=[8001, 8002, 8003],
                       help="Node ports to connect to")
    parser.add_argument("--auto", action="store_true",
                       help="Run automated tests instead of interactive mode")
    
    args = parser.parse_args()
    
    tester = NetworkTester(args.ports)
    tester.print_banner()
    
    if not tester.check_all_nodes():
        print("❌ Some nodes are not healthy. Please check your network setup.")
        return
    
    if args.auto:
        print("🤖 Running automated tests...")
        
        # Automated test sequence
        print("\n1. Adding random transactions...")
        for _ in range(5):
            tester.add_random_transaction()
            time.sleep(0.5)
        
        print("\n2. Mining blocks...")
        for i in range(3):
            tester.mine_block(i % len(args.ports), f"AutoMiner{i+1}", 10.0)
            time.sleep(3)
        
        print("\n3. Final state:")
        tester.show_chain_summary()
        
        print("\n4. Running stress test...")
        tester.stress_test(15, 2)
        
        print("\n✅ Automated tests completed!")
    else:
        tester.interactive_menu()

if __name__ == "__main__":
    main()