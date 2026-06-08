export const mockPriceOracleAbi = [
  {
    "type": "function",
    "name": "clearResolvedValue",
    "inputs": [
      {
        "name": "series",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getResolvedValue",
    "inputs": [
      {
        "name": "series",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "resolved",
        "type": "bool",
        "internalType": "bool"
      },
      {
        "name": "value",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "setResolvedValue",
    "inputs": [
      {
        "name": "series",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "value",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  }
] as const;

export const mockPriceOracleBytecode = "0x608060405234801561000f575f80fd5b506101b08061001d5f395ff3fe608060405234801561000f575f80fd5b506004361061003f575f3560e01c806347b4f316146100435780634ffc7b4b14610077578063c9955028146100c6575b5f80fd5b610075610051366004610132565b6001600160a01b03165f908152602081905260408120805460ff1916815560010155565b005b6100ab610085366004610132565b6001600160a01b03165f908152602081905260409020805460019091015460ff90911691565b60408051921515835260208301919091520160405180910390f35b6100756100d4366004610152565b604080518082018252600180825260208083019485526001600160a01b03959095165f90815294859052919093209251835460ff19169015151783559051910155565b80356001600160a01b038116811461012d575f80fd5b919050565b5f60208284031215610142575f80fd5b61014b82610117565b9392505050565b5f8060408385031215610163575f80fd5b61016c83610117565b94602093909301359350505056fea2646970667358221220c9c29c4b024ec95e0b7d2ba7caf272b9381ae00d734028be0ca679aab32a2ea564736f6c63430008180033" as `0x${string}`;
