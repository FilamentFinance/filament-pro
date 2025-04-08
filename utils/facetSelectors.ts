const diamondLoupeFacetSelectors = ["0xcdffacc6", "0x52ef6b2c", "0xadfca15e", "0x7a0ed627", "0x01ffc9a7"]

const ownershipFacetSelectors = ["0x8da5cb5b", "0xf2fde38b"]

const tradeFacetSelectors = [
    "0xbe2d0e3a", // increasePosition((uint256,uint256,uint256,uint256,uint256,uint256,int256,address,address,uint8,uint8,bool)) |
    "0xc59caebc", // decreasePosition((uint256,uint256,uint256,uint256,uint256,uint256,int256,address,address,uint8,uint8,bool)) |
    "0x4bee5e11", // transferPosition(address,address,bool,uint256,uint256,uint256,uint256,uint256,int256) |
    "0xc39ad3aa", // liquidateMatchWithPoolADL(address,address,bool,uint256,int256,uint256,uint256,uint256) |
    "0xffe22117", // hourlyFeeDistribution(address,uint256,bytes32[],int256[]) |
    "0xae6a6fd1", // borrowFeeDistribution(address,uint256) |
    "0xccc17b1e", // fundingFeeDistribution(address,bytes32[],int256[]) |
    "0x6b8a99e7", // getCurrentCollateral(bytes32,uint256,int256,uint256,uint256) |
    "0xa03b4898", // validateliquidation(bytes32,uint256,int256,uint256,uint256) |
    "0xb86c6ea0", // addLPFees(uint256,address) |
    "0x4ba7cf2d", // getNextAveragePrice(uint256,uint256,bool,uint256,uint256) |
    "0x60707712", // getDelta(uint256,uint256,bool,uint256) |
    "0xc1e725b8", // getTransferPositionSizeAndPrice(bytes32,int256) |
    "0x34f15124", // getLiquidationPositionSizeAndPrice(bytes32) |
    "0x4494f672" // maxAvailableUSDC(address) |
]

const vaultFacetSelectors = [
    "0x8456cb59", // pause() |
    "0x3f4ba83a", // unpause() |
    "0xcf3ffdf1", // addSequencer(address[]) |
    "0x6989ca7c", // removeSequencer(address) |
    "0x24ca984e", // addRouter(address) |
    "0xc39155af", // updateDustSize(uint256) |
    "0xc1aafb8b", // updateMaxLiquidatorLeverageToAcquirePosition(uint256) |
    "0x775d6994", // addIndexToken(address) |
    "0x2a5d2cd0", // updateEpochDuration(uint256) |
    "0x8ae471fb", // addCompartmentalizationTime(uint256) |
    "0x89c1684a", // addOptimalUtilization(uint256,address) |
    "0x83fab159", // setADLPercentage(address,uint256) |
    "0x5de766a6", // updateLiquidationLeverage(address,uint256) |
    "0x05741f7c", // updatePositionForLiquidator(bytes32,bytes32,(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,int256,address,bool)) |
    "0xcc224d44", // addEscrow(address) |
    "0x6b369507", // addProtocolLiquidator(address) |
    "0x9467a93a", // addLpTokenContract(address) |
    "0xf1d21c1c", // addKeeperContract(address) |
    "0x91372379", // addDepositContract(address) |
    "0x5575ad3a", // setUSDCContract(address) |
    "0xd3127e63", // setMaxLeverage(uint256) |
    "0xc40f98c1", // updateCombPoolLimit(uint256) |
    "0xaa63a0a4", // addNewAsset(address[],uint256[]) |
    "0xe5da2cb2", // stakeLP(uint256) |
    "0xc4778998", // unstakeLP(uint256) |
    "0x379607f5", // claim(uint256) |
    "0xdf92a5d1", // compartmentalize() |
    "0x9c8f9f23", // removeLiquidity(uint256) |
    "0xbdeda833", // redeemLPTokens(uint256) |
    "0x369e6ff2", // updateCollateralFromLiquidation((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,int256,address,bool),bytes32) |
    "0x51c6590a", // addLiquidity(uint256) |
    "0xd71275f6", // getBorrowRate(address) |
    "0x8a19bf66", // maxWithdrawableAmount() |
    "0x0865a8a3", // addInterestRateParams((address,uint256,uint256,uint256,uint256)[]) |
    "0x2c8e9715", // updateInterestRateParams((address,uint256,uint256,uint256,uint256)) |
    "0xb17cb742", // addExtraCollateral(address) |
    "0xeed18491", // moveCollateralFromRemovedAsset(address, address)
    "0x83900828", // updateCollateralMappings(address,uint256,uint256)
    "0x5d08b370", // deletePositionMitigateRisk(address,address,address,bool,uint256)
    "0x34f2c07f", // deleteDustPosition(bytes32),
    "0xbd2d1f45" // createPosition(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,int256,address,bool)
]

const viewFacetSelectors = [
    "0xcbfe81bf", // isSequencerWhitelisted(address) |
    "0x1f11777c", // getLastLiquidationLeverageUpdateTime(address) |
    "0xc4d126ed", // getLiquidationLeverage(address) |
    "0x65f49632", // getADLpercentage(address) |
    "0x4ff0876a", // epochDuration() |
    "0x5c2987df", // compartmentalizationTime() |
    "0x1ce20023", // getLastTradedPrice(address) |
    "0x62f3a2a3", // compartments(address) |
    "0x82f07388", // borrowedAmountFromPool(address) |
    "0x8b0d1789", // compartmentBorrowDetails(address) |
    "0xc081c177", // allIndexTokens(uint256) |
    "0xc1998bb6", // getTotalOBTradedSize(address) |
    "0xc0380bac", // getTotalIndexTokens() |
    "0x43dfb029", // getDustSize() |
    "0x035eb918", // getLongCollateral(address) |
    "0xf773a8bc", // getShortCollateral(address) |
    "0xb97a2d13", // getUsdBalance() |
    "0xa83066b2", // totalBorrowedUSD() |
    "0xfb1995ae", // isValidIndexToken(address) |
    "0x2a47e29a", // getMaxLiquidatorLeverageToAcquirePosition() |
    "0x2d4b0576", // getPositionKey(address,address,address,bool) |
    "0x1928b3cb", // getPosition(bytes32) |
    "0xca403772", // getPositionSize(address,address,bool) |
    "0xdb7a5c34", // getOptimalUtilization(address) |
    "0xaea143ae", // getRouterContract() |
    "0xc9e57aa6", // getLPTokenAddress() |
    "0xab94276a", // getDepositContract() |
    "0xe4a94743", // getUSDCContract() |
    "0xb909acc5", // getEscrowContract() |
    "0x38706949", // isProtocolLiquidatorAddress(address) |
    "0x7f8e5883", // getKeeperContract() |
    "0x16934fc4", // stakes(address) |
    "0xe12f3a61", // getClaimableAmount(address) |
    "0xcde45320", // getTotalFLPStaked() |
    "0x74adad1d", // requests(address) |
    "0xf398f8b0" // getInterestRateParams(address) |
]

export {
    tradeFacetSelectors,
    vaultFacetSelectors,
    viewFacetSelectors,
    diamondLoupeFacetSelectors,
    ownershipFacetSelectors
}
