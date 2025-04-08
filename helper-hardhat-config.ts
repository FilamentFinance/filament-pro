export interface TradeFeeDistribution {
    referralPortion: string
    lp: string
    protocolTreasury: string
    filamentTokenStakers: string
    insurance: string
}

export interface BorrowFeeDistribution {
    lp: string
    protocolTreasury: string
}

export interface InterestRateParam {
    Bs: string
    S1: string
    S2: string
    Uo: string
}

export interface networkConfigItem {
    chainId: number
    goldskySlug: string
    deployer: string
    usdc?: string
    protocolTreasury: string
    liquidators: string[]
    insurance: string
    sequencers: string[]
    assetAddresses: string[]
    percentage: number[]
    combPoolLimit: string
    tradeFeeDistribution: TradeFeeDistribution
    borrowFeeDistribution: BorrowFeeDistribution
    interestRateParam: InterestRateParam
    multisigOwners?: string[]
    multisigConfirms?: number
}

export interface networkConfigInfo {
    [key: string]: networkConfigItem
}

export const networkConfig: networkConfigInfo = {
    hardhat: {
        chainId: 31337,
        goldskySlug: "hardhat",
        usdc: "0x27A1c3791578dDdd27De4F1A21d4c0E699e45939",
        deployer: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        protocolTreasury: "0x976EA74026E726554dB657fA54763abd0C3a0aa9",
        liquidators: ["0x14dC79964da2C08b23698B3D3cc7Ca32193d9955"],
        insurance: "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720",
        sequencers: [
            "0xBcd4042DE499D14e55001CcbB24a551F3b954096",
            "0x71bE63f3384f5fb98995898A86B02Fb2426c5788",
            "0xFABB0ac9d68B0B445fB7357272Ff202C5651694a"
        ],
        assetAddresses: [
            "0x152b9d0FdC40C096757F570A51E494bd4b943E50", // BTC
            "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", // ETH
            "0x7DfF46370e9eA5f0Bad3C4E29711aD50062EA7A4", // SOL
            "0x9c1cb740f3b631ed53600058ae5b2f83e15d9fbf" // SEI
        ],
        percentage: [5000, 2500, 1500, 1000],
        combPoolLimit: "10000000000000000000000000",
        tradeFeeDistribution: {
            referralPortion: "0",
            lp: "4500",
            protocolTreasury: "4500",
            filamentTokenStakers: "0",
            insurance: "1000"
        },
        borrowFeeDistribution: {
            lp: "7500",
            protocolTreasury: "2500"
        },
        interestRateParam: {
            Bs: "10000",
            S1: "3000",
            S2: "7500",
            Uo: "8000"
        }
    },
    localhost: {
        chainId: 31337,
        goldskySlug: "localhost",
        usdc: "0x27A1c3791578dDdd27De4F1A21d4c0E699e45939",
        deployer: "0x91C2352245065B9e5d2514a313b60c1f01BfF60F",
        protocolTreasury: "0x81F20658e0265d89f4Cca7BAf8FB3933B4FcA6Be",
        liquidators: ["0x7a2B49798c9f122bD95df22C8B0EA9dB784c062e"],
        insurance: "0xA0f1D96FC1C93A24A89eF10f27eBF097275f3b86",
        sequencers: [
            "0x7494CbFF585b42F28FeFE8A4043dDB5A17781a2c",
            "0xA2439545C6CD0D6B0679cbbBBc6cE7921ed8d9c9",
            "0xa9d3338B983cb663C6aA85cA49D56C096670254F"
        ],
        assetAddresses: [
            "0x152b9d0FdC40C096757F570A51E494bd4b943E50", // BTC
            "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", // ETH
            "0x7DfF46370e9eA5f0Bad3C4E29711aD50062EA7A4", // SOL
            "0x9c1cb740f3b631ed53600058ae5b2f83e15d9fbf" // SEI
        ],
        percentage: [5000, 2500, 1500, 1000],
        combPoolLimit: "10000000000000000000000000",
        tradeFeeDistribution: {
            referralPortion: "0",
            lp: "4500",
            protocolTreasury: "4500",
            filamentTokenStakers: "0",
            insurance: "1000"
        },
        borrowFeeDistribution: {
            lp: "7500",
            protocolTreasury: "2500"
        },
        interestRateParam: {
            Bs: "10000",
            S1: "3000",
            S2: "7500",
            Uo: "8000"
        }
    },
    seiTestnet: {
        chainId: 1328,
        goldskySlug: "sei-testnet",
        usdc: "0x27A1c3791578dDdd27De4F1A21d4c0E699e45939",
        deployer: "0x91C2352245065B9e5d2514a313b60c1f01BfF60F",
        protocolTreasury: "0xF75d74a2f4B3B1EF8051E159cDc9f1bA7E4772ab",
        liquidators: ["0xe277b604f83ad0B28bDd09614F6b0C337c98Bf11", "0xbCffe4c42E8186B4770d5269015940E074D2eE00"],
        insurance: "0x6694afc5F15BfA52bE215a802E81A6cbD540e2aC",
        sequencers: [
            "0x7494CbFF585b42F28FeFE8A4043dDB5A17781a2c",
            "0xA2439545C6CD0D6B0679cbbBBc6cE7921ed8d9c9",
            "0xa9d3338B983cb663C6aA85cA49D56C096670254F"
        ],
        assetAddresses: [
            "0x152b9d0FdC40C096757F570A51E494bd4b943E50", // BTC
            "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", // ETH
            "0x7DfF46370e9eA5f0Bad3C4E29711aD50062EA7A4", // SOL
            "0x9c1cb740f3b631ed53600058ae5b2f83e15d9fbf" // SEI
        ],
        percentage: [5000, 2500, 1500, 1000],
        combPoolLimit: "10000000000000000000000000",
        tradeFeeDistribution: {
            referralPortion: "0",
            lp: "4500",
            protocolTreasury: "4500",
            filamentTokenStakers: "0",
            insurance: "1000"
        },
        borrowFeeDistribution: {
            lp: "7500",
            protocolTreasury: "2500"
        },
        interestRateParam: {
            Bs: "10000",
            S1: "3000",
            S2: "7500",
            Uo: "8000"
        },
        multisigOwners: [
            "0x91C2352245065B9e5d2514a313b60c1f01BfF60F",
            "0x02d4Bf54Fe8bA630fFc2862a6393C462967D5a1D",
            "0xBf7Ac59948Fb15A24Fe9a97699294b3F7b7f1300"
        ],
        multisigConfirms: 2
    },
    seiMainnet: {
        chainId: 1329,
        goldskySlug: "sei",
        deployer: "0xc060695ecd8ee28d1cf11cdd27c7f368e86986c5",
        usdc: "0x3894085Ef7Ff0f0aeDf52E2A2704928d1Ec074F1",
        protocolTreasury: "0xf38BdB166222A423528c38bD719F7Ae15E90dEbE",
        liquidators: ["0x1cbB9A313AD4A50459283F2C2Ac74A5dA0689007", "0xbCffe4c42E8186B4770d5269015940E074D2eE00"],
        insurance: "0x121B34238CC8A2Bc5DFA22c2C3ac0964b1E3264b",
        sequencers: [
            "0x055c93c096260fB3d1AD375730daBa88495c0c6e",
            "0xD3705760C43340818E0d5f74BFBD1366F3321DC4",
            "0x7c2AAc24b37E806B3A6A6421daEf7288e426574c"
        ],
        assetAddresses: [
            "0x152b9d0FdC40C096757F570A51E494bd4b943E50", // BTC
            "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", // ETH
            "0x7DfF46370e9eA5f0Bad3C4E29711aD50062EA7A4", // SOL
            "0x9c1cb740f3b631ed53600058ae5b2f83e15d9fbf" // SEI
        ],
        percentage: [5000, 2500, 1500, 1000],
        combPoolLimit: "10000000000000000000000000",
        tradeFeeDistribution: {
            referralPortion: "0",
            lp: "4500",
            protocolTreasury: "4500",
            filamentTokenStakers: "0",
            insurance: "1000"
        },
        borrowFeeDistribution: {
            lp: "7500",
            protocolTreasury: "2500"
        },
        interestRateParam: {
            Bs: "10000",
            S1: "3000",
            S2: "7500",
            Uo: "8000"
        },
        multisigOwners: ["0xc060695ecd8ee28d1cf11cdd27c7f368e86986c5"],
        multisigConfirms: 3
    }
}

export const forkedChain = ["localhost"]
export const testNetworkChains = ["seiTestnet"]
export const VERIFICATION_BLOCK_CONFIRMATIONS = 6
