#!/usr/bin/env python3
"""
Bitcoin Network Demo Script
Demonstrates key features of the mini Bitcoin network
"""

import requests
import json
import time
import sys
from typing import List

def print_header(title: str):
    print("\n" + "="*60)
    print(f"🚀 {title}")
    print("="*60)

def print_step(step: int, description: str):
    print(f"\n📍 Step {step}: {description}")
    print("-" * 40)

def check_nodes_health(nodes: List[str]) -> bool:
    """Check if all nodes are healthy"""
    print("🔍 Checking node health...")
    all_healthy = True
    
    for i, node in enumerate(nodes):
        try:
            response = requests.get(f"{node}/health", timeout=5)
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Node {i+1} ({node}): Height {data['height']}, {data['peers']} peers")
            else:
                print(f"❌ Node {i+1} ({node}): HTTP {response.status_code}")
                all_healthy = False
        except Exception as e:
            print(f"❌ Node {i+1} ({node}): {str(e)}")
            all_healthy = False
    
    return all_healthy

def add_transaction(node: str, sender: str, recipient: str, amount: float):
    """Add a transaction to a node"""
    transaction = {
        "sender": sender,
        "recipient": recipient,  
        "amount": amount
    }
    
    try:
        response = requests.post(f"{node}/transaction", json=transaction, timeout=10)
        if response.status_code == 201:
            result = response.json()
            print(f"✅ Transaction added: {sender} → {recipient} ({amount} BTC)")
            print(f"   Pool size: {result['pool_size']}")
            return True
        else:
            print(f"❌ Failed to add transaction: HTTP {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Failed to add transaction: {str(e)}")
        return False

def mine_block(node: str, miner: str, reward: float = 12.5):
    """Mine a block on specified node"""
    print(f"⛏️  Mining block on {node}...")
    print(f"   Miner: {miner}, Reward: {reward} BTC")
    
    try:
        start_time = time.time()
        response = requests.get(f"{node}/mine", 
                              params={"miner": miner, "reward": reward}, 
                              timeout=60)
        mining_time = time.time() - start_time
        
        if response.status_code == 200:
            result = response.json()
            block = result['block']
            print(f"✅ Block #{block['index']} mined successfully!")
            print(f"   Hash: {block['hash'][:20]}...")
            print(f"   Nonce: {block['nonce']}")
            print(f"   Transactions: {len(block['transactions'])}")
            print(f"   Mining time: {mining_time:.2f}s")
            print(f"   Broadcasted to: {result.get('broadcasted_to', 0)} peers")
            return True
        else:
            print(f"❌ Mining failed: HTTP {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Mining failed: {str(e)}")
        return False

def get_chain_length(node: str) -> int:
    """Get blockchain length from node"""
    try:
        response = requests.get(f"{node}/chain", timeout=10)
        if response.status_code == 200:
            return response.json()["length"]
        return 0
    except:
        return 0

def check_synchronization(nodes: List[str]) -> bool:
    """Check if all nodes have synchronized chains"""
    print("🔄 Checking chain synchronization...")
    
    lengths = []
    for i, node in enumerate(nodes):
        length = get_chain_length(node)
        lengths.append(length)
        print(f"   Node {i+1}: {length} blocks")
    
    all_same = all(l == lengths[0] for l in lengths)
    
    if all_same and lengths[0] > 0:
        print(f"✅ All nodes synchronized ({lengths[0]} blocks)")
        return True
    else:
        print(f"❌ Nodes not synchronized: {lengths}")
        return False

def show_latest_block(node: str):
    """Show details of the latest block"""
    try:
        response = requests.get(f"{node}/chain", timeout=10)
        if response.status_code == 200:
            chain = response.json()["chain"]
            if chain:
                latest_block = chain[-1]
                print(f"📦 Latest Block (#{latest_block['index']}):")
                print(f"   Hash: {latest_block['hash']}")
                print(f"   Previous: {latest_block['previous_hash'][:20]}...")
                print(f"   Timestamp: {time.ctime(latest_block['timestamp'])}")
                print(f"   Difficulty: {latest_block['difficulty']}")
                print(f"   Nonce: {latest_block['nonce']}")
                print(f"   Transactions: {len(latest_block['transactions'])}")
                
                # Show transactions
                for i, tx in enumerate(latest_block['transactions']):
                    print(f"     {i+1}. {tx['sender']} → {tx['recipient']}: {tx['amount']} BTC")
    except Exception as e:
        print(f"❌ Failed to get latest block: {str(e)}")

def show_mempool(node: str):
    """Show transaction pool of a node"""
    try:
        response = requests.get(f"{node}/transactions/pool", timeout=10)
        if response.status_code == 200:
            pool = response.json()
            print(f"💰 Transaction Pool ({pool['count']} transactions):")
            for i, tx in enumerate(pool['transactions']):
                print(f"   {i+1}. {tx['sender']} → {tx['recipient']}: {tx['amount']} BTC")
        else:
            print(f"❌ Failed to get mempool: HTTP {response.status_code}")
    except Exception as e:
        print(f"❌ Failed to get mempool: {str(e)}")

def wait_for_sync(nodes: List[str], max_wait: int = 30):
    """Wait for nodes to synchronize"""
    print(f"⏳ Waiting for synchronization (max {max_wait}s)...")
    
    for i in range(max_wait):
        if check_synchronization(nodes):
            return True
        time.sleep(1)
        if i % 5 == 4:  # Progress indicator every 5 seconds
            print(f"   Still waiting... ({i+1}s)")
    
    print(f"⚠️  Synchronization timeout after {max_wait}s")
    return False

def demonstrate_conflict_resolution(nodes: List[str]):
    """Demonstrate chain conflict resolution"""
    print_step(5, "Demonstrating Conflict Resolution")
    
    # First, ensure all nodes are synchronized
    wait_for_sync(nodes, 10)
    
    # Add transactions to create some activity
    print("\n🔄 Creating chain divergence scenario...")
    
    # Add transactions to different nodes
    add_transaction(nodes[0], "Alice", "Bob", 15.0)
    add_transaction(nodes[1], "Charlie", "Dave", 25.0)
    
    # Mine on first node
    print(f"\n⛏️  Mining on Node 1...")
    mine_block(nodes[0], "Miner1", 10.0)
    
    # Wait a bit and check lengths
    time.sleep(3)
    
    lengths_before = [get_chain_length(node) for node in nodes]
    print(f"Chain lengths before resolution: {lengths_before}")
    
    # Force conflict resolution on all nodes
    print("\n🔄 Triggering conflict resolution...")
    for i, node in enumerate(nodes):
        try:
            response = requests.get(f"{node}/resolve", timeout=15)
            if response.status_code == 200:
                result = response.json()
                print(f"   Node {i+1}: Chain length {result['length']}, Replaced: {result['replaced']}")
        except Exception as e:
            print(f"   Node {i+1}: Resolution failed - {str(e)}")
    
    # Final synchronization check
    time.sleep(5)
    if wait_for_sync(nodes, 15):
        print("✅ Conflict resolution successful!")
    else:
        print("❌ Conflict resolution may have issues")

def full_demo():
    """Run complete demonstration"""
    # Node configuration
    NODES = [
        "http://localhost:8001",
        "http://localhost:8002", 
        "http://localhost:8003"
    ]
    
    print_header("Mini Bitcoin Network Demo")
    print("This demo will showcase the key features of our Bitcoin network:")
    print("• Transaction processing")
    print("• Block mining") 
    print("• Chain synchronization")
    print("• Conflict resolution")
    print("\nMake sure you have started the network with:")
    print("./network_manager.sh start")
    
    input("\nPress Enter to continue...")
    
    # Step 1: Check network health
    print_step(1, "Network Health Check")
    if not check_nodes_health(NODES):
        print("\n❌ Some nodes are not healthy. Please check your setup.")
        print("Run: ./network_manager.sh start")
        sys.exit(1)
    
    # Step 2: Show initial state
    print_step(2, "Initial Network State")
    show_latest_block(NODES[0])
    check_synchronization(NODES)
    
    # Step 3: Add transactions
    print_step(3, "Adding Transactions")
    
    transactions = [
        ("Alice", "Bob", 10.5),
        ("Bob", "Charlie", 5.0),
        ("Charlie", "Dave", 15.0),
        ("Dave", "Eve", 8.5),
        ("Eve", "Alice", 3.0)
    ]
    
    print("Adding sample transactions...")
    successful_txs = 0
    for sender, recipient, amount in transactions:
        # Distribute transactions across different nodes
        node_index = successful_txs % len(NODES)
        if add_transaction(NODES[node_index], sender, recipient, amount):
            successful_txs += 1
        time.sleep(0.5)
    
    print(f"\n✅ Successfully added {successful_txs}/{len(transactions)} transactions")
    
    # Show mempool state
    print("\n💰 Current mempool state:")
    show_mempool(NODES[0])
    
    # Step 4: Mining demonstration
    print_step(4, "Mining Demonstration")
    
    print("Mining first block...")
    if mine_block(NODES[0], "Alice", 12.5):
        # Wait for propagation
        print("\n⏳ Waiting for block propagation...")
        time.sleep(5)
        
        # Check synchronization
        if wait_for_sync(NODES, 15):
            print("✅ Block successfully propagated to all nodes!")
            show_latest_block(NODES[0])
        else:
            print("⚠️  Block propagation may be slow")
    
    # Mine another block from different node
    print("\n⛏️  Mining second block from different node...")
    add_transaction(NODES[1], "Frank", "Grace", 20.0)
    add_transaction(NODES[1], "Grace", "Henry", 7.5)
    
    if mine_block(NODES[1], "Bob", 12.5):
        time.sleep(5)
        wait_for_sync(NODES, 15)
        show_latest_block(NODES[0])
    
    # Step 5: Conflict resolution demo
    demonstrate_conflict_resolution(NODES)
    
    # Step 6: Final state
    print_step(6, "Final Network State")
    
    print("📊 Final blockchain summary:")
    for i, node in enumerate(NODES):
        length = get_chain_length(node)
        print(f"   Node {i+1}: {length} blocks")
    
    show_latest_block(NODES[0])
    
    # Show empty mempool
    print("\n💰 Final mempool state:")
    show_mempool(NODES[0])
    
    print_header("Demo Completed Successfully! 🎉")
    print("Key features demonstrated:")
    print("✅ Transaction broadcasting")
    print("✅ Proof-of-Work mining") 
    print("✅ Block propagation")
    print("✅ Chain synchronization")
    print("✅ Conflict resolution")
    print("\nTry the interactive tester for more features:")
    print("python network_tester.py")

def stress_test_demo():
    """Run stress test demonstration"""
    NODES = [
        "http://localhost:8001",
        "http://localhost:8002", 
        "http://localhost:8003"
    ]
    
    print_header("Network Stress Test Demo")
    
    if not check_nodes_health(NODES):
        print("❌ Nodes not healthy. Exiting.")
        sys.exit(1)
    
    print("🔥 Starting stress test with:")
    print("• 20 transactions")
    print("• 5 mining rounds")
    print("• Concurrent operations")
    
    input("Press Enter to start stress test...")
    
    # Add many transactions rapidly
    print("\n📈 Phase 1: Rapid transaction generation")
    names = ["Alice", "Bob", "Charlie", "Dave", "Eve", "Frank", "Grace", "Henry", "Ivan", "Julia"]
    
    for i in range(20):
        import random
        sender = random.choice(names)
        recipient = random.choice([n for n in names if n != sender])
        amount = round(random.uniform(1, 50), 2)
        node = NODES[i % len(NODES)]
        
        add_transaction(node, sender, recipient, amount)
        time.sleep(0.1)  # Small delay to avoid overwhelming
    
    print("✅ Transaction flood completed")
    
    # Show mempool sizes
    print("\n💰 Mempool sizes after transaction flood:")
    for i, node in enumerate(NODES):
        try:
            response = requests.get(f"{node}/transactions/pool", timeout=5)
            if response.status_code == 200:
                count = response.json()["count"]
                print(f"   Node {i+1}: {count} transactions")
        except:
            print(f"   Node {i+1}: Unable to check")
    
    # Mining stress test
    print("\n📈 Phase 2: Concurrent mining")
    
    for round_num in range(5):
        print(f"\n⛏️  Mining Round {round_num + 1}")
        
        # Pick random node for mining
        node_index = round_num % len(NODES)
        miner_name = f"StressMiner{round_num + 1}"
        
        mine_block(NODES[node_index], miner_name, 10.0 + round_num)
        
        # Brief wait between rounds
        time.sleep(3)
    
    print("\n📈 Phase 3: Final synchronization check")
    
    if wait_for_sync(NODES, 30):
        print("✅ Stress test completed successfully!")
        
        # Final statistics
        final_length = get_chain_length(NODES[0])
        print(f"\n📊 Final Statistics:")
        print(f"   • Final chain length: {final_length} blocks")
        print(f"   • All nodes synchronized: ✅")
        
        show_latest_block(NODES[0])
    else:
        print("⚠️  Some synchronization issues detected")

def main():
    """Main function with demo options"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Bitcoin Network Demo")
    parser.add_argument("--mode", choices=["full", "stress"], default="full",
                       help="Demo mode: full demonstration or stress test")
    parser.add_argument("--nodes", nargs="+", default=["8001", "8002", "8003"],
                       help="Node ports")
    
    args = parser.parse_args()
    
    # Update global nodes list if custom ports provided
    global NODES
    NODES = [f"http://localhost:{port}" for port in args.nodes]
    
    if args.mode == "full":
        full_demo()
    elif args.mode == "stress":
        stress_test_demo()

if __name__ == "__main__":
    main()