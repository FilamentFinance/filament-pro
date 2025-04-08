import { ethers, upgrades, network } from "hardhat"
import { updateContractsJson } from "../utils/updateContracts"
import verify from "../utils/verify"
import { networkConfig, testNetworkChains } from "../helper-hardhat-config"
import fs from "fs"
import {
    tradeFacetSelectors,
    vaultFacetSelectors,
    viewFacetSelectors,
    diamondLoupeFacetSelectors,
    ownershipFacetSelectors
} from "../utils/facetSelectors"

import { FacetCutAction } from "../utils/constants"

const main = async () => {
    let tx, txr, usdAddress
    const accounts = await ethers.getSigners()
    const networkName = network.name
    const owner = accounts[0].address
    const deployer = networkConfig[networkName].deployer

    if (deployer?.toLowerCase() !== owner.toLowerCase()) {
        throw Error("Deployer must be the Owner")
    }
    console.log(owner)

    const protocolTreasury = networkConfig[networkName].protocolTreasury
    const liquidators = networkConfig[networkName].liquidators
    const insuranceWallet = networkConfig[networkName].insurance
    const sequencers = networkConfig[networkName].sequencers
    const assetAddresses = networkConfig[networkName].assetAddresses
    const per = networkConfig[networkName].percentage
    const combPoolLimit = networkConfig[networkName].combPoolLimit
    const tradeFeeDistribution = networkConfig[networkName].tradeFeeDistribution
    const borrowFeeDistribution = networkConfig[networkName].borrowFeeDistribution
    const interestRateParam = networkConfig[networkName].interestRateParam
    const multisigOwners = networkConfig[networkName].multisigOwners
    const multisigConfirms = networkConfig[networkName].multisigConfirms || 1000

    let ozExist = fs.existsSync(`.openzeppelin/unknown-${network.config.chainId}.json`)
    if (ozExist) {
        console.log("%c Deleting existing OpenZeppelin deployment file", "color:red")
        fs.rmSync(`.openzeppelin/unknown-${network.config.chainId}.json`)
    }

    // Deploy USDC and other Tokens contract
    const startBlock: any = await ethers.provider.getBlock("latest")
    console.log(startBlock!.number)
    let USDC
    if (networkName !== "hardhat") {
        usdAddress = { target: networkConfig[networkName].usdc }
    } else {
        USDC = await ethers.getContractFactory("USDCF")
        const usdcNew = await upgrades.deployProxy(USDC, ["USDC Filament", "USDFIL"])
        usdAddress = await usdcNew.waitForDeployment()
        console.log("USDC deployed to:", usdAddress.target)
    }

    // // Deploy LpToken contract
    const LpToken = await ethers.getContractFactory("LpToken")
    const lpToken = await upgrades.deployProxy(LpToken, [usdAddress.target, "Filament LP Token", "FLP"])
    const lpTokenAddress = await lpToken.waitForDeployment()
    console.log("LpToken deployed to:", lpTokenAddress.target)

    // // Deploy Keeper contract
    const Keeper = await ethers.getContractFactory("Keeper")
    const keeper = await upgrades.deployProxy(Keeper, [usdAddress.target, protocolTreasury, insuranceWallet])
    const keeperAddress = await keeper.waitForDeployment()
    console.log("Keeper deployed to:", keeperAddress.target)

    const Deposit = await ethers.getContractFactory("Deposit")
    const deposit = await upgrades.deployProxy(Deposit, [usdAddress.target])
    const depositAddress = await deposit.waitForDeployment()
    console.log("Deposit deployed to:", depositAddress.target)

    // Deploy Router
    const Router = await ethers.getContractFactory("Router")
    const router = await upgrades.deployProxy(Router, [])
    const routerAddress = await router.waitForDeployment()
    console.log("Router deployed to:", routerAddress.target)

    // Deploy Escrow
    const Escrow = await ethers.getContractFactory("Escrow")
    const escrow = await upgrades.deployProxy(Escrow, [usdAddress.target]) // @note-rajeeb: _bot: for transferring position from TradeFacet to Escrow
    const escrowAddress = await escrow.waitForDeployment()
    console.log("escrow deployed to:", escrowAddress.target)

    // Deploy IncentiveAlloc
    const IncentiveAlloc = await ethers.getContractFactory("IncentiveAlloc")
    const incentiveAlloc = await upgrades.deployProxy(IncentiveAlloc, [])
    const incentiveAllocAddress = await incentiveAlloc.waitForDeployment()
    console.log("incentiveAlloc deployed to:", incentiveAllocAddress.target)

    // deploy DiamondCutFacet
    const DiamondCutFacet = await ethers.getContractFactory("DiamondCutFacet")
    const diamondCutFacet = await DiamondCutFacet.deploy()
    await diamondCutFacet.waitForDeployment()
    console.log("DiamondCutFacet deployed:", diamondCutFacet.target)

    const DiamondLoupeFacet = await ethers.getContractFactory("DiamondLoupeFacet")
    const diamondLoupeFacet = await DiamondLoupeFacet.deploy()
    await diamondLoupeFacet.waitForDeployment()
    console.log("DiamondLoupeFacet deployed:", diamondLoupeFacet.target)

    // @note-rajeeb: Need to add selectors from ownership facet as well right ? or, we don't need?
    const OwnershipFacet = await ethers.getContractFactory("OwnershipFacet")
    const ownershipFacet = await OwnershipFacet.deploy()
    await ownershipFacet.waitForDeployment()
    console.log("OwnershipFacet deployed:", ownershipFacet.target)

    const TradeFacet = await ethers.getContractFactory("TradeFacet")
    const tradeFacet = await TradeFacet.deploy()
    await tradeFacet.waitForDeployment()
    console.log("TradeFacet deployed:", tradeFacet.target)

    const VaultFacet = await ethers.getContractFactory("VaultFacet")
    const vaultFacet = await VaultFacet.deploy()
    await vaultFacet.waitForDeployment()
    console.log("VaultFacet deployed:", vaultFacet.target)

    const ViewFacet = await ethers.getContractFactory("ViewFacet")
    const viewFacet = await ViewFacet.deploy()
    await viewFacet.waitForDeployment()
    console.log("ViewFacet deployed:", viewFacet.target)

    const DiamondInit = await ethers.getContractFactory("DiamondInit")
    const diamondInit = await DiamondInit.deploy()
    await diamondInit.waitForDeployment()
    console.log("DiamondInit deployed:", diamondInit.target)

    const Diamond = await ethers.getContractFactory("Diamond")
    const diamond = await Diamond.deploy(owner, diamondCutFacet.target)
    await diamond.waitForDeployment()
    console.log("Diamond deployed:", diamond.target)

    const cut = []

    cut.push({
        facetAddress: diamondLoupeFacet.target,
        action: FacetCutAction.Add,
        functionSelectors: diamondLoupeFacetSelectors
    })

    cut.push({
        facetAddress: tradeFacet.target,
        action: FacetCutAction.Add,
        functionSelectors: tradeFacetSelectors
    })
    cut.push({
        facetAddress: vaultFacet.target,
        action: FacetCutAction.Add,
        functionSelectors: vaultFacetSelectors
    })

    cut.push({
        facetAddress: viewFacet.target,
        action: FacetCutAction.Add,
        functionSelectors: viewFacetSelectors
    })

    cut.push({
        facetAddress: ownershipFacet.target,
        action: FacetCutAction.Add,
        functionSelectors: ownershipFacetSelectors
    })

    const diamondCut = await ethers.getContractAt("IDiamondCut", diamond.target)

    let functionCall = diamondInit.interface.encodeFunctionData("init", [])
    tx = await diamondCut.diamondCut(cut, diamondInit.target, functionCall)
    console.log("Diamond cut tx: ", tx.hash)
    txr = await tx.wait()
    if (!txr?.status) {
        throw Error(`Diamond cut failed: ${tx.hash}`)
    }
    console.log("Completed diamond cut")

    const rout: any = await Router.attach(routerAddress.target)
    const rout2 = await rout.setDiamondContract(diamond.target)
    let r1 = await rout2.wait()

    if (!r1.status) {
        throw Error(`failed to set diamond address in Router Contract: `)
    }

    const es: any = await Escrow.attach(escrowAddress.target)
    const es2 = await es.setDiamondContract(diamond.target)
    let r2 = await es2.wait()

    if (!r2.status) {
        throw Error(`failed to set address in Escrow Contract: `)
    }

    const vault: any = VaultFacet.attach(diamond.target)
    const result = await vault.addNewAsset(assetAddresses, per)
    let receipt1 = await result.wait()
    if (!receipt1.status) {
        throw Error(`failed to add assets: `)
    }

    const intrstRtPrm = assetAddresses.map((addr: any) => {
        return {
            indexToken: addr,
            Bs: interestRateParam.Bs,
            S1: interestRateParam.S1,
            S2: interestRateParam.S2,
            Uo: interestRateParam.Uo
        }
    })
    const for1 = await vault.addInterestRateParams(intrstRtPrm)
    const resF2 = await for1.wait()

    if (!resF2.status) {
        throw Error(` borrow rate parms not added  `)
    }

    tx = await vault.addSequencer(sequencers)
    txr = await tx.wait()
    console.log("Sequencers added")

    tx = await vault.addRouter(routerAddress.target)
    txr = await tx.wait()
    console.log("Router added")

    for (let i = 0; i < liquidators.length; i++) {
        tx = await vault.addProtocolLiquidator(networkConfig[networkName].liquidators[i])
        txr = await tx.wait()
        console.log("Liquidator address added", liquidators[i])
    }

    tx = await vault.addLpTokenContract(lpTokenAddress.target)
    txr = await tx.wait()
    console.log("LP token address added")

    tx = await vault.addKeeperContract(keeperAddress.target)
    txr = await tx.wait()
    console.log("Keeper address added")

    tx = await vault.addDepositContract(depositAddress.target)
    txr = await tx.wait()
    console.log("Deposit address added")

    tx = await vault.setUSDCContract(networkConfig[networkName].usdc)
    txr = await tx.wait()
    console.log("USDC address added")

    // const trade = await TradeFacet.attach(diamond.target)

    const compartmentalisationTime = await vault.addCompartmentalizationTime(3600)
    let compartmentalisationTime1 = await compartmentalisationTime.wait()
    if (!compartmentalisationTime1.status) {
        throw Error(`failed to add assets: `)
    }
    // const updateEpochDuration = await vault.updateEpochDuration(72)
    // let updateEpochDuration1 = await updateEpochDuration.wait()
    // if (!updateEpochDuration1.status) {
    //     throw Error(`failed to add assets: `)
    // }

    for (let i = 0; i < assetAddresses.length; i++) {
        // tx = await vault.updateCollateralizationRatio(assetAddresses[i], 2000)
        tx = await vault.updateLiquidationLeverage(assetAddresses[i], 80)
        txr = await tx.wait(1)
        if (!txr.status) {
            throw Error(`failed to updateMaxLeverage: ${assetAddresses[i]}`)
        }
        tx = await vault.addOptimalUtilization(8000, assetAddresses[i])
        txr = await tx.wait(1)
        if (!txr.status) {
            throw Error(`failed to add Optimal Utilization: ${assetAddresses[i]}`)
        }
        tx = await vault.setADLPercentage(assetAddresses[i], 9000)
        txr = await tx.wait(1)
        if (!txr.status) {
            throw Error(`failed to add ADL percentage: ${assetAddresses[i]}`)
        }
    }
    const addescrowAddr = await vault.addEscrow(escrowAddress.target)
    let receipt2 = await addescrowAddr.wait()
    if (!receipt2.status) {
        throw Error(`failed to add escrow: `)
    }

    const setCombPoolLimitTx = await vault.updateCombPoolLimit(combPoolLimit)
    let receipt4 = await setCombPoolLimitTx.wait()
    if (!receipt4.status) {
        throw Error(`failed to comb pool limit `)
    }

    const lp: any = await LpToken.attach(lpTokenAddress.target)
    const lpres = await lp.setDiamondAddress(diamond.target)
    let lpresWait = await lpres.wait()
    if (!lpresWait.status) {
        throw Error(`failed to add lp functions `)
    }

    const kepperC: any = Keeper.attach(keeperAddress.target)
    const res1 = await kepperC.setDiamondContract(diamond.target)
    let res1Wait = await res1.wait()

    const res3 = await kepperC.updateTradingFeeDistribution(tradeFeeDistribution)
    let res3Wait = await res3.wait()

    const res4 = await kepperC.updateBorrowingFeeDistribution(borrowFeeDistribution)
    let res4Wait = await res4.wait()

    if (!res1Wait.status && !res3Wait.status && !res4Wait.status) {
        throw Error(`failed to add lp functions : `)
    }

    const dep: any = await Deposit.attach(depositAddress.target)
    const depRes = await dep.setDiamondContract(diamond.target)
    const d1 = await depRes.wait()

    tx = await dep.pause()
    await tx.wait()

    if (!d1.status) {
        throw Error(`failed to add deposit functions : `)
    }

    let multiSigWallet = { target: "0x0000000000000000000000000000000000000000" }

    if (multisigOwners && multisigOwners.length > 0 && multisigConfirms < multisigOwners.length) {
        // Deploy MultiSig
        const MultiSigWallet = await ethers.getContractFactory("MultiSigWallet")
        console.log("Deploying MultiSigWallet...")

        let requiredConfirmations = networkConfig[networkName].multisigConfirms || 1
        let multiSigWallet = await MultiSigWallet.deploy(multisigOwners, requiredConfirmations)
        console.log("MultiSigWallet deployed to:", multiSigWallet.target)

        // const ownership: any = OwnershipFacet.attach(diamond.target)
        // transferOwnership to MultiSigWallet
        // tx = await ownership.transferOwnership(multiSigWallet.target)
        // await tx.wait(1)
        // tx = await dep.transferOwnership(multiSigWallet.target)
        // await tx.wait(1)
        // tx = await rout.transferOwnership(multiSigWallet.target)
        // await tx.wait(1)
        // tx = await es.transferOwnership(multiSigWallet.target)
        // await tx.wait(1)
        // const keeperC: any = await Keeper.attach(keeperAddress.target)
        // tx = await keeperC.transferOwnership(multiSigWallet.target)
        // await tx.wait(1)
        // const LpTokenC: any = await LpToken.attach(lpTokenAddress.target)
        // tx = await LpTokenC.transferOwnership(multiSigWallet.target)
        // await tx.wait(1)
    }

    let contracts = [
        { name: "USDC", address: usdAddress.target },
        { name: "LpToken", address: lpTokenAddress.target },
        { name: "Keeper", address: keeperAddress.target },
        { name: "Deposit", address: depositAddress.target },
        { name: "DiamondCutFacet", address: diamondCutFacet.target },
        { name: "DiamondLoupeFacet", address: diamondLoupeFacet.target },
        { name: "OwnershipFacet", address: ownershipFacet.target },
        { name: "TradeFacet", address: tradeFacet.target },
        { name: "VaultFacet", address: vaultFacet.target },
        { name: "ViewFacet", address: viewFacet.target },
        { name: "DiamondInit", address: diamondInit.target },
        { name: "Diamond", address: diamond.target },
        { name: "Router", address: routerAddress.target },
        { name: "Escrow", address: escrowAddress.target },
        { name: "IncentiveAlloc", address: incentiveAllocAddress.target },
        { name: "MultiSigWallet", address: multiSigWallet.target },
        { name: "StartBlock", address: startBlock.number },
        {
            name: "Goldsky_Subgraph",
            address:
                "https://api.goldsky.com/api/public/project_cm0qvthsz96sp01utcnk55ib0/subgraphs/filament-sei-testnet/v2/gn"
        }
    ]

    updateContractsJson(contracts)
    // createSubgraphConfig()
    console.table(contracts)

    if (
        testNetworkChains.includes(networkName) &&
        process.env.SEITRACE_API_KEY &&
        process.env.VERIFY_CONTRACTS === "true"
    ) {
        console.log("Verifying...")
        await verify(usdAddress?.target?.toString() ?? "", [])
        await verify(lpTokenAddress?.target?.toString() ?? "", [])
        await verify(keeperAddress?.target?.toString() ?? "", [])
        await verify(depositAddress?.target?.toString() ?? "", [])
        await verify(routerAddress?.target?.toString() ?? "", [])
        await verify(escrowAddress.target.toString(), [])
        await verify(diamond.target.toString(), [owner, diamondCutFacet.target])
        await verify(diamondLoupeFacet.target.toString(), [])
        await verify(diamondCutFacet.target.toString(), [])
        await verify(diamondInit.target.toString(), [])
        await verify(tradeFacet.target.toString(), [])
        await verify(vaultFacet.target.toString(), [])
        await verify(viewFacet.target.toString(), [])
    }
    console.log("🚀🚀🚀 Deployment Successful 🚀🚀🚀")
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
