import { HardhatUserConfig } from "hardhat/config"
import "@nomicfoundation/hardhat-toolbox"
import "@openzeppelin/hardhat-upgrades"
import "@nomicfoundation/hardhat-foundry"
import * as dotenv from "dotenv"
import "solidity-docgen"
import "hardhat-abi-exporter"
import "hardhat-contract-sizer"
import "@nomiclabs/hardhat-solhint"
// import "@tenderly/hardhat-tenderly"
dotenv.config()

const PRIVATE_KEY_ADMIN = process.env.PRIVATE_KEY_ADMIN || ""
const PRIVATE_KEY_TWO = process.env.PRIVATE_KEY_TWO || ""
const PRIVATE_KEY_SEQ = process.env.PRIVATE_KEY_SEQ || ""
const SEITRACE_API_KEY = process.env.SEITRACE_API_KEY || ""
const PRIVATE_KEY_LIQUIDATOR = process.env.PRIVATE_KEY_LIQUIDATOR || ""
const PRIVATE_KEY_ADMIN2 = process.env.PRIVATE_KEY_ADMIN2 || ""

const config: HardhatUserConfig = {
    paths: {
        sources: "contracts",
        tests: "tests"
    },
    solidity: {
        compilers: [
            {
                version: "0.8.27",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 300
                    },
                    viaIR: true
                }
            },
            {
                version: "0.8.26",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 300
                    },
                    viaIR: true
                }
            }
        ]
    },
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            chainId: 31337
            // forking: {
            //     url: "https://evm-rpc-testnet.sei-apis.com"
            //     // blockNumber: 115142278
            // }
        },
        localhost: {
            chainId: 31337,
            forking: {
                url: "https://evm-rpc-testnet.sei-apis.com"
                // blockNumber: 115142278
            },
            accounts: [PRIVATE_KEY_ADMIN, PRIVATE_KEY_TWO, PRIVATE_KEY_SEQ, PRIVATE_KEY_LIQUIDATOR]
        },
        seiTestnet: {
            url: "https://evm-rpc-testnet.sei-apis.com",
            chainId: 1328,
            accounts: [PRIVATE_KEY_ADMIN, PRIVATE_KEY_TWO, PRIVATE_KEY_SEQ, PRIVATE_KEY_LIQUIDATOR]
        },
        seiMainnet: {
            url: "https://evm-rpc.sei-apis.com",
            chainId: 1329,
            accounts: [PRIVATE_KEY_ADMIN, PRIVATE_KEY_TWO, PRIVATE_KEY_SEQ, PRIVATE_KEY_LIQUIDATOR],
            gasPrice: 6000000000
        }
    },
    abiExporter: {
        path: "./constants/abis",
        runOnCompile: true,
        clear: true,
        flat: true,
        spacing: 4,
        only: [
            "Deposit",
            "TradeFacet",
            "VaultFacet",
            "ViewFacet",
            "OwnershipFacet",
            "Diamond",
            "DiamondLoupeFacet",
            "USDCF",
            "Router",
            "LpToken",
            "Keeper",
            "Escrow",
            "MultiSigWallet",
            "ProxyDemo",
            "Credits",
            "FilamentMigration",
            "IncentiveAlloc"
        ]
    },
    sourcify: {
        enabled: false
    },
    etherscan: {
        apiKey: {
            seiTestnet: SEITRACE_API_KEY,
            seiMainnet: SEITRACE_API_KEY
        },
        customChains: [
            {
                network: "seiTestnet",
                chainId: 1328,
                urls: {
                    apiURL: "https://seitrace.com/atlantic-2/api",
                    browserURL: "https://seitrace.com"
                }
            },
            {
                network: "seiMainnet",
                chainId: 1329,
                urls: {
                    apiURL: "https://seitrace.com/pacific-1/api",
                    browserURL: "https://seitrace.com"
                }
            }
        ]
    },
    docgen: {
        outputDir: "./docs",
        pages: "files",
        collapseNewlines: true
    },
    contractSizer: {
        alphaSort: true,
        disambiguatePaths: false,
        runOnCompile: false,
        strict: true
        // only: [":ERC20$"]
    },
    gasReporter: {
        currency: "USD",
        enabled: false,
        excludeContracts: [],
        showTimeSpent: true,
        token: "ETH"
    },
    mocha: {
        timeout: 150000
    }
}

export default config
