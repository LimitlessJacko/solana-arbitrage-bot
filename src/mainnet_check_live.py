#!/usr/bin/env python3
"""
Mainnet Live Check for Solana Arbitrage Bot
Demonstrates real-time LP supply fetching and profit calculation
"""

import asyncio
import logging
import time
from decimal import Decimal
import sys
import os

# Add src directory to path
sys.path.append(os.path.join(os.path.dirname(__file__)))

from market_data import MarketDataProvider
from optimizer import ArbitrageOptimizer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class LiveArbitrageChecker:
    """Live arbitrage opportunity checker for mainnet"""
    
    def __init__(self):
        self.market_data = MarketDataProvider()
        self.optimizer = ArbitrageOptimizer()
        
    async def initialize(self):
        """Initialize the live checker"""
        logger.info("🚀 Initializing Live Arbitrage Checker...")
        await self.market_data.initialize()
        logger.info("✅ Live checker initialized")
        
    async def check_live_opportunities(self):
        """Check for live arbitrage opportunities"""
        start_time = time.time()
        
        try:
            # Fetch real-time market data
            logger.info("📊 Fetching live market data...")
            market_data = await self.market_data.get_all_prices()
            
            if not market_data:
                logger.warning("⚠️  No market data available")
                return
                
            # Find profitable routes
            logger.info("🔍 Analyzing arbitrage opportunities...")
            profitable_routes = await self.optimizer.find_profitable_routes(market_data)
            
            # Display results
            elapsed_time = time.time() - start_time
            logger.info(f"⏱️  Analysis completed in {elapsed_time:.2f}s")
            
            if profitable_routes:
                logger.info(f"💰 Found {len(profitable_routes)} profitable opportunities:")
                
                for i, route in enumerate(profitable_routes[:3], 1):  # Show top 3
                    borrow_amount = route['amount']
                    profit = route['profit']
                    confidence = route['confidence']
                    
                    logger.info(f"  {i}. Borrowed: {borrow_amount:,.0f} SOL → Profit: ${profit:,.0f} @ {confidence:.0%} confidence")
                    logger.info(f"     Route: {' → '.join(route['path'])}")
                    
                # Simulate the best opportunity
                best_route = profitable_routes[0]
                await self.simulate_execution(best_route)
                
            else:
                logger.info("📉 No profitable opportunities found at current market conditions")
                
        except Exception as e:
            logger.error(f"❌ Error checking opportunities: {e}")
            
    async def simulate_execution(self, route):
        """Simulate execution of the best route"""
        logger.info("🎯 Simulating execution of best opportunity...")
        
        borrow_amount = route['amount']
        expected_profit = route['profit']
        confidence = route['confidence']
        
        # Simulate transaction steps
        steps = [
            f"1. Flash borrow {borrow_amount:,.0f} SOL from Solend",
            f"2. Execute swaps via {' → '.join(route['path'])}",
            f"3. Repay flash loan + fees",
            f"4. Net profit: ${expected_profit:,.0f}"
        ]
        
        for step in steps:
            logger.info(f"   {step}")
            await asyncio.sleep(0.2)  # Simulate processing time
            
        logger.info(f"✅ Simulation complete - Estimated profit: ${expected_profit:,.0f}")
        
    async def run_continuous_check(self, interval=5):
        """Run continuous arbitrage checking"""
        logger.info(f"🔄 Starting continuous monitoring (every {interval}s)...")
        
        cycle_count = 0
        while True:
            try:
                cycle_count += 1
                logger.info(f"\n{'='*60}")
                logger.info(f"🔄 Cycle #{cycle_count} - {time.strftime('%H:%M:%S')}")
                logger.info(f"{'='*60}")
                
                await self.check_live_opportunities()
                
                logger.info(f"⏳ Waiting {interval}s for next cycle...")
                await asyncio.sleep(interval)
                
            except KeyboardInterrupt:
                logger.info("\n🛑 Stopping continuous monitoring...")
                break
            except Exception as e:
                logger.error(f"❌ Error in cycle {cycle_count}: {e}")
                await asyncio.sleep(interval)
                
    async def close(self):
        """Clean up resources"""
        await self.market_data.close()

async def main():
    """Main entry point for live checking"""
    print("""
    ╔══════════════════════════════════════════════════════════════╗
    ║                 SOLANA ARBITRAGE BOT - LIVE CHECK            ║
    ║                                                              ║
    ║  🚀 Real-time LP supply fetching and profit calculation     ║
    ║  💰 Live arbitrage opportunity detection                     ║
    ║  ⚡ Sub-second market analysis                               ║
    ╚══════════════════════════════════════════════════════════════╝
    """)
    
    checker = LiveArbitrageChecker()
    
    try:
        await checker.initialize()
        
        # Check command line arguments
        if len(sys.argv) > 1 and sys.argv[1] == '--continuous':
            await checker.run_continuous_check()
        else:
            # Single check
            await checker.check_live_opportunities()
            
    except KeyboardInterrupt:
        logger.info("\n👋 Goodbye!")
    except Exception as e:
        logger.error(f"❌ Fatal error: {e}")
    finally:
        await checker.close()

if __name__ == "__main__":
    # Example usage:
    # python mainnet_check_live.py           # Single check
    # python mainnet_check_live.py --continuous  # Continuous monitoring
    
    asyncio.run(main())

