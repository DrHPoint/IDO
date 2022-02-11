const hre = require("hardhat");

async function main() {
  
  //const NFT = await hre.ethers.getContractFactory("NFT");
  //const nft = await NFT.deploy();

  //await nft.deployed();
  
  const Bridge = await hre.ethers.getContractFactory("Bridge");
  const bridge = await Bridge.deploy(process.env.NFT_ADDR, 4); //97

  await bridge.deployed();

  //console.log("Nft deployed to:", nft.address);
  console.log("Bridge deployed to:", bridge.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
