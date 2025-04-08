import * as fs from "fs"
import * as path from "path"

// Define the folder structure root
const CONTRACTS_DIR = "./constants/abis"

// Define the regex pattern to search for
const PATTERN = /error\s+[A-Za-z0-9_]+\([^)]*\);/g

// Function to recursively get all Solidity (.sol) files from a directory
function getABIFiles(dir: string): string[] {
    let results: string[] = []
    const list = fs.readdirSync(dir)

    list.forEach((file) => {
        const filePath = path.join(dir, file)
        const stat = fs.statSync(filePath)

        if (stat && stat.isDirectory()) {
            results = results.concat(getABIFiles(filePath)) // Recursion for subdirectories
        } else if (filePath.endsWith(".json")) {
            results.push(filePath) // Add Solidity file
        }
    })

    return results
}

// Function to search for the pattern in Solidity files
function searchPatternInFiles(files: string[], pattern: RegExp) {
    let errorSelector: any[] = []
    files.forEach((file) => {
        const abi = fs.readFileSync(file, "utf8")
        const errors = JSON.parse(abi).filter((item: any) => item.type === "error")

        errors.forEach((error: any) => {
            const name = error.name
            const types = error.inputs.map((input: any) => input.type).join(",")
            const selector = `${name}(${types})`
            const signature = ethers.keccak256(ethers.toUtf8Bytes(selector)).slice(0, 10) // First 4 bytes (8 hex characters)
            // console.log(`Error: ${error.name}, Signature: ${signature}`)
            errorSelector.push({ code: signature, name: selector })
        })
    })
    console.log(JSON.stringify(errorSelector))
}

// Get all Solidity files
const solidityFiles = getABIFiles(CONTRACTS_DIR)

// Search for the pattern in each Solidity file
searchPatternInFiles(solidityFiles, PATTERN)
