"""
Arbitrage Optimizer for Solana Flash Loan Bot
Finds and optimizes profitable arbitrage routes across DEXs
"""

import asyncio
import logging
from typing import Dict, List, Optional, Any, Tuple
from decimal import Decimal
from dataclasses import dataclass
import itertools
import math

logger = logging.getLogger(__name__)

@dataclass
class Route:
    """Represents an arbitrage route"""
    path: List[str]
    token_pair: str
    estimated_profit: Decimal
    confidence: float
    gas_cost: Decimal
    net_profit: Decimal
    
@dataclass
class PoolInfo:
    """Information about a liquidity pool"""
    dex: str
    token_a: str
    token_b: str
    reserve_a: Decimal
    reserve_b: Decimal
    fee: Decimal
    liquidity: Decimal

class ArbitrageOptimizer:
    """Optimizes arbitrage opportunities across Solana DEXs"""
    
    def __init__(self):
        self.min_profit_threshold = Decimal('10.0')  # Minimum $10 profit
        self.max_slippage = Decimal('0.02')  # 2% max slippage
        self.gas_price_estimate = Decimal('0.01')  # $0.01 per transaction
        
    async def find_profitable_routes(self, market_data: Dict[str, List[Any]]) -> List[Dict[str, Any]]:
        """Find profitable arbitrage routes from market data"""
        logger.info("Analyzing market data for profitable routes...")
        
        profitable_routes = []
        
        # Convert market data to pool information
        pools = self._convert_to_pools(market_data)
        
        # Find triangular arbitrage opportunities
        triangular_routes = await self._find_triangular_arbitrage(pools)
        profitable_routes.extend(triangular_routes)
        
        # Find direct arbitrage opportunities (same pair, different DEXs)
        direct_routes = await self._find_direct_arbitrage(market_data)
        profitable_routes.extend(direct_routes)
        
        # Filter and sort by profitability
        filtered_routes = self._filter_profitable_routes(profitable_routes)
        
        logger.info(f"Found {len(filtered_routes)} profitable routes")
        return filtered_routes
        
    def _convert_to_pools(self, market_data: Dict[str, List[Any]]) -> List[PoolInfo]:
        """Convert market data to pool information"""
        pools = []
        
        for symbol, price_list in market_data.items():
            for price_data in price_list:
                # Parse token pair
                if '/' in symbol:
                    token_a, token_b = symbol.split('/')
                    
                    # Estimate reserves based on liquidity and price
                    total_liquidity = price_data.liquidity
                    price = price_data.price
                    
                    # Simple estimation (in reality, this would be more complex)
                    reserve_a = total_liquidity / (2 * price)
                    reserve_b = total_liquidity / 2
                    
                    pool = PoolInfo(
                        dex=price_data.source.lower(),
                        token_a=token_a,
                        token_b=token_b,
                        reserve_a=reserve_a,
                        reserve_b=reserve_b,
                        fee=Decimal('0.003'),  # 0.3% typical DEX fee
                        liquidity=total_liquidity
                    )
                    pools.append(pool)
                    
        return pools
        
    async def _find_triangular_arbitrage(self, pools: List[PoolInfo]) -> List[Dict[str, Any]]:
        """Find triangular arbitrage opportunities (A->B->C->A)"""
        logger.info("Searching for triangular arbitrage opportunities...")
        
        routes = []
        
        # Group pools by tokens
        token_pools = {}
        for pool in pools:
            for token in [pool.token_a, pool.token_b]:
                if token not in token_pools:
                    token_pools[token] = []
                token_pools[token].append(pool)
                
        # Find triangular paths
        base_tokens = ['SOL', 'USDC', 'USDT']  # Common base tokens
        
        for base_token in base_tokens:
            if base_token not in token_pools:
                continue
                
            # Find all possible triangular paths starting with base_token
            triangular_paths = self._find_triangular_paths(base_token, token_pools)
            
            for path in triangular_paths:
                profit_analysis = await self._analyze_triangular_profit(path, pools)
                
                if profit_analysis['net_profit'] > self.min_profit_threshold:
                    routes.append({
                        'pair': f"{base_token}_TRIANGULAR",
                        'amount': profit_analysis['optimal_amount'],
                        'profit': profit_analysis['net_profit'],
                        'confidence': profit_analysis['confidence'],
                        'path': path,
                        'gas_estimate': profit_analysis['gas_cost'],
                        'type': 'triangular'
                    })
                    
        return routes
        
    def _find_triangular_paths(self, base_token: str, token_pools: Dict[str, List[PoolInfo]]) -> List[List[str]]:
        """Find all possible triangular arbitrage paths"""
        paths = []
        
        # Get all tokens that can be traded with base_token
        connected_tokens = set()
        for pool in token_pools.get(base_token, []):
            other_token = pool.token_b if pool.token_a == base_token else pool.token_a
            connected_tokens.add(other_token)
            
        # Find triangular paths: base -> token1 -> token2 -> base
        for token1 in connected_tokens:
            for token2 in connected_tokens:
                if token1 != token2:
                    # Check if token1 -> token2 -> base path exists
                    if self._path_exists(token1, token2, token_pools) and \
                       self._path_exists(token2, base_token, token_pools):
                        path = [base_token, token1, token2, base_token]
                        paths.append(path)
                        
        return paths
        
    def _path_exists(self, token_a: str, token_b: str, token_pools: Dict[str, List[PoolInfo]]) -> bool:
        """Check if a trading path exists between two tokens"""
        for pool in token_pools.get(token_a, []):
            if (pool.token_a == token_a and pool.token_b == token_b) or \
               (pool.token_a == token_b and pool.token_b == token_a):
                return True
        return False
        
    async def _analyze_triangular_profit(self, path: List[str], pools: List[PoolInfo]) -> Dict[str, Any]:
        """Analyze profit potential of a triangular arbitrage path"""
        
        # Start with different amounts to find optimal
        test_amounts = [Decimal('100'), Decimal('1000'), Decimal('10000'), Decimal('100000')]
        best_profit = Decimal('0')
        best_amount = Decimal('1000')
        
        for amount in test_amounts:
            current_amount = amount
            gas_cost = Decimal('0')
            
            # Simulate the triangular trade
            for i in range(len(path) - 1):
                from_token = path[i]
                to_token = path[i + 1]
                
                # Find the best pool for this trade
                best_pool = self._find_best_pool(from_token, to_token, pools)
                if not best_pool:
                    current_amount = Decimal('0')
                    break
                    
                # Calculate output amount after trade
                output_amount = self._calculate_swap_output(
                    current_amount, best_pool, from_token == best_pool.token_a
                )
                
                current_amount = output_amount
                gas_cost += self.gas_price_estimate
                
            # Calculate net profit
            net_profit = current_amount - amount - gas_cost
            
            if net_profit > best_profit:
                best_profit = net_profit
                best_amount = amount
                
        # Calculate confidence based on liquidity and slippage
        confidence = self._calculate_confidence(path, pools, best_amount)
        
        return {
            'optimal_amount': best_amount,
            'gross_profit': best_profit + (len(path) - 1) * self.gas_price_estimate,
            'net_profit': best_profit,
            'gas_cost': (len(path) - 1) * self.gas_price_estimate,
            'confidence': confidence
        }
        
    async def _find_direct_arbitrage(self, market_data: Dict[str, List[Any]]) -> List[Dict[str, Any]]:
        """Find direct arbitrage opportunities (same pair, different DEXs)"""
        logger.info("Searching for direct arbitrage opportunities...")
        
        routes = []
        
        for symbol, price_list in market_data.items():
            if len(price_list) < 2:
                continue
                
            # Sort by price
            sorted_prices = sorted(price_list, key=lambda x: x.price)
            lowest = sorted_prices[0]
            highest = sorted_prices[-1]
            
            # Calculate potential profit
            price_diff = highest.price - lowest.price
            percentage_diff = (price_diff / lowest.price) * 100
            
            if percentage_diff > 0.5:  # More than 0.5% difference
                # Calculate optimal trade amount
                optimal_amount = self._calculate_optimal_direct_amount(lowest, highest)
                
                if optimal_amount > 0:
                    gross_profit = optimal_amount * price_diff
                    gas_cost = 2 * self.gas_price_estimate  # Buy + Sell
                    net_profit = gross_profit - gas_cost
                    
                    if net_profit > self.min_profit_threshold:
                        routes.append({
                            'pair': symbol,
                            'amount': optimal_amount,
                            'profit': net_profit,
                            'confidence': min(0.95, percentage_diff / 10),  # Higher diff = higher confidence
                            'path': [lowest.source, highest.source],
                            'gas_estimate': gas_cost,
                            'type': 'direct'
                        })
                        
        return routes
        
    def _find_best_pool(self, from_token: str, to_token: str, pools: List[PoolInfo]) -> Optional[PoolInfo]:
        """Find the best pool for a token swap"""
        best_pool = None
        best_rate = Decimal('0')
        
        for pool in pools:
            if (pool.token_a == from_token and pool.token_b == to_token) or \
               (pool.token_a == to_token and pool.token_b == from_token):
                
                # Calculate exchange rate
                if pool.token_a == from_token:
                    rate = pool.reserve_b / pool.reserve_a
                else:
                    rate = pool.reserve_a / pool.reserve_b
                    
                if rate > best_rate:
                    best_rate = rate
                    best_pool = pool
                    
        return best_pool
        
    def _calculate_swap_output(self, input_amount: Decimal, pool: PoolInfo, a_to_b: bool) -> Decimal:
        """Calculate output amount for a swap using constant product formula"""
        if a_to_b:
            input_reserve = pool.reserve_a
            output_reserve = pool.reserve_b
        else:
            input_reserve = pool.reserve_b
            output_reserve = pool.reserve_a
            
        # Apply fee
        input_amount_with_fee = input_amount * (Decimal('1') - pool.fee)
        
        # Constant product formula: x * y = k
        # output = (input_with_fee * output_reserve) / (input_reserve + input_with_fee)
        numerator = input_amount_with_fee * output_reserve
        denominator = input_reserve + input_amount_with_fee
        
        return numerator / denominator
        
    def _calculate_optimal_direct_amount(self, low_price_data: Any, high_price_data: Any) -> Decimal:
        """Calculate optimal amount for direct arbitrage"""
        # Consider liquidity constraints
        max_amount_low = low_price_data.liquidity / (4 * low_price_data.price)  # Use 25% of liquidity
        max_amount_high = high_price_data.liquidity / (4 * high_price_data.price)
        
        # Take the minimum to avoid excessive slippage
        optimal_amount = min(max_amount_low, max_amount_high)
        
        # Ensure minimum viable amount
        return max(optimal_amount, Decimal('100'))
        
    def _calculate_confidence(self, path: List[str], pools: List[PoolInfo], amount: Decimal) -> float:
        """Calculate confidence score for a route"""
        confidence_factors = []
        
        # Liquidity factor
        min_liquidity = float('inf')
        for i in range(len(path) - 1):
            pool = self._find_best_pool(path[i], path[i + 1], pools)
            if pool:
                min_liquidity = min(min_liquidity, float(pool.liquidity))
                
        liquidity_score = min(1.0, min_liquidity / 1000000)  # Normalize to $1M
        confidence_factors.append(liquidity_score)
        
        # Amount factor (lower amounts = higher confidence)
        amount_score = max(0.1, 1.0 - (float(amount) / 1000000))  # Normalize to $1M
        confidence_factors.append(amount_score)
        
        # Path length factor (shorter paths = higher confidence)
        path_score = max(0.5, 1.0 - ((len(path) - 2) * 0.1))
        confidence_factors.append(path_score)
        
        # Calculate weighted average
        return sum(confidence_factors) / len(confidence_factors)
        
    def _filter_profitable_routes(self, routes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter and sort routes by profitability"""
        # Filter by minimum profit
        profitable = [r for r in routes if r['profit'] > self.min_profit_threshold]
        
        # Sort by profit descending
        profitable.sort(key=lambda x: x['profit'], reverse=True)
        
        # Limit to top 10 routes
        return profitable[:10]
        
    async def optimize_route_timing(self, route: Dict[str, Any]) -> Dict[str, Any]:
        """Optimize the timing for route execution"""
        # TODO: Implement timing optimization based on:
        # - Network congestion
        # - Gas prices
        # - Market volatility
        # - Liquidity changes
        
        optimized_route = route.copy()
        optimized_route['optimal_execution_time'] = 'immediate'
        optimized_route['estimated_execution_duration'] = 5  # seconds
        
        return optimized_route
        
    async def calculate_slippage_impact(self, route: Dict[str, Any], pools: List[PoolInfo]) -> Decimal:
        """Calculate expected slippage impact for a route"""
        total_slippage = Decimal('0')
        
        if route['type'] == 'triangular':
            path = route['path']
            amount = route['amount']
            
            for i in range(len(path) - 1):
                pool = self._find_best_pool(path[i], path[i + 1], pools)
                if pool:
                    # Calculate slippage for this hop
                    slippage = self._calculate_single_swap_slippage(amount, pool)
                    total_slippage += slippage
                    
        return total_slippage
        
    def _calculate_single_swap_slippage(self, amount: Decimal, pool: PoolInfo) -> Decimal:
        """Calculate slippage for a single swap"""
        # Simplified slippage calculation
        # In reality, this would be more sophisticated
        liquidity_ratio = amount / pool.liquidity
        slippage = liquidity_ratio * Decimal('0.1')  # 10% slippage per 100% of liquidity
        
        return min(slippage, self.max_slippage)

