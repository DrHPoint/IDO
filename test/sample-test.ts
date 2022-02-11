import { expect } from "chai";
import { Contract, ContractFactory, Signer, utils } from "ethers";
import { parseEther, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { hexConcat } from "@ethersproject/bytes";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

let IDO : ContractFactory;
let ido : Contract;
let ERC20 : ContractFactory;
let token : Contract;
let Reward : ContractFactory;
let reward : Contract;
let Reward2 : ContractFactory;
let reward2 : Contract;
let FailReward : ContractFactory;
let fail : Contract;
let user: SignerWithAddress;
let owner: SignerWithAddress;
let addr1: SignerWithAddress;
let addr2: SignerWithAddress;
let addr3: SignerWithAddress;
let addr4: SignerWithAddress;

describe("Hermes", function () {

  beforeEach(async () => {
    ERC20 = await ethers.getContractFactory("MyToken");
    Reward = await ethers.getContractFactory("MyToken");
    Reward2 = await ethers.getContractFactory("MyToken");
    FailReward = await ethers.getContractFactory("MyToken");
    IDO = await ethers.getContractFactory("IDO");
  });

  describe("Stacking", () => {

    it("0) Deploy, mint and get allowance", async function() {
      [owner, user, addr1, addr2, addr3, addr4] = await ethers.getSigners();
      token = await ERC20.connect(owner).deploy();
      reward = await Reward.connect(owner).deploy();
      reward2 = await Reward2.connect(owner).deploy();
      fail = await FailReward.connect(owner).deploy();
      ido = await IDO.connect(owner).deploy();

    });


    it("1.1) Deploy", async function() {
      await token.deployed();
      await reward.deployed();
      await reward2.deployed();
      await fail.deployed();
      await ido.deployed();
    });

    it("1.2) Mint", async function() {
      await reward.connect(owner).mint(user.address, parseUnits("4000", 18));
      await fail.connect(owner).mint(user.address, parseUnits("4000", 18));
      await reward2.connect(owner).mint(user.address, parseUnits("80000000", 18));
      
      await token.connect(owner).mint(addr1.address, parseUnits("2000", 18));
      await token.connect(owner).mint(addr2.address, parseUnits("2000", 18));
      await token.connect(owner).mint(addr3.address, parseUnits("2000", 18));
      await token.connect(owner).mint(addr4.address, parseUnits("2000", 18));
      await token.connect(owner).mint(owner.address, parseUnits("2000", 18));
    });

    it("1.3) Get allowance", async function() {
      await token.connect(addr1).approve(ido.address, parseUnits("3000", 18));
      await token.connect(addr2).approve(ido.address, parseUnits("2000", 18));
      await token.connect(addr3).approve(ido.address, parseUnits("2000", 18));
      await token.connect(addr4).approve(ido.address, parseUnits("2000", 18));
      await token.connect(owner).approve(ido.address, parseUnits("2000", 18));
    });

    it("2) 1st round: Create Campaign", async function() {
      
      const vestings = [{ percent: ethers.utils.parseEther("0.25"), timestamp: (3600 * 24) }, { percent: ethers.utils.parseEther("0.5"), timestamp: (2 * (3600 * 24)) }, { percent: ethers.utils.parseEther("1"), timestamp: (3 * (3600 * 24)) }];
      const blockTimestamp = ((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp);
      await ido.connect(owner).create({minAllocation: parseUnits("100", 18), maxAllocation: parseUnits("1000", 18), minGoal: parseUnits("2000", 18), maxGoal: parseUnits("4000", 18), total: 0, price: parseUnits("1", 18), startTime: blockTimestamp + 3600, endTime: blockTimestamp + 13 * 3600, acquireAddress: token.address, rewardAddress: reward.address, acquireDecimals: 18, rewardDecimals: 18, status: 0}, vestings);
    
    });

    it("3) 1st round: Try to join", async function() {
      await expect(ido.connect(addr1).join(0, parseUnits("1000", 18))).to.be.revertedWith("Not right time to join this campaign");
    });

    it("4) 1st round: After 1 hour join with customers", async function() {
      
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("0", 18));

      await ido.connect(addr1).join(0, parseUnits("2000", 18));

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("1000", 18));

      await ido.connect(addr2).join(0, parseUnits("500", 18));
      await ido.connect(addr2).join(0, parseUnits("750", 18));

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("2000", 18));

      await ido.connect(addr3).join(0, parseUnits("1000", 18));
      await expect(ido.connect(addr3).join(0, parseUnits("1000", 18))).to.be.revertedWith("User have max allocation");
      
      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("3000", 18));
      
      await ido.connect(addr4).join(0, parseUnits("1000", 18));

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("4000", 18));

      await expect(ido.connect(owner).join(0, parseUnits("1000", 18))).to.be.revertedWith("Goal amount already collected");

    });

    it("5) 1st round: After 10 hours try to claim and after refund, also try to approve", async function() {

      await ethers.provider.send("evm_increaseTime", [3600 * 10]);
      await ethers.provider.send("evm_mine", []);

      await expect(ido.connect(addr1).claim(0)).to.be.revertedWith("This campaign already not claiming");
      await expect(ido.connect(addr1).refund(0)).to.be.revertedWith("This campaign already not refunding");

      await expect(ido.connect(owner).approve(0)).to.be.revertedWith("Too early for approve");

    });

    it("6) 1st round: After 12 hours approve, try approve again and try to refund", async function() {

      await ethers.provider.send("evm_increaseTime", [3600 * 2]);
      await ethers.provider.send("evm_mine", []);

      await reward.connect(owner).mint(ido.address, parseUnits("4000", 18));

      await ido.connect(owner).approve(0);

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("0", 18));
      await expect(ido.connect(owner).approve(0)).to.be.revertedWith("Not actual campaign");

      await expect(ido.connect(addr1).refund(0)).to.be.revertedWith("This campaign already not refunding");

    });

    it("7) 1st round: Claim and after one more hour claim again", async function() {

      expect(await reward.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("0", 18));
      console.log(0);
      await expect(ido.connect(addr1).claim(0)).to.be.revertedWith("Already nothing to claim");

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);

      await ido.connect(addr1).claim(0);

      console.log(0);

      expect(await reward.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("250", 18));

      await expect(ido.connect(addr1).claim(0)).to.be.revertedWith("Already nothing to claim");
    

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);

      await ido.connect(addr1).claim(0);

      expect(await reward.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("500", 18));
    
      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);

      await ido.connect(addr1).claim(0);

      expect(await reward.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("1000", 18));

      await expect(ido.connect(addr1).claim(0)).to.be.revertedWith("All sum already claimed");

    });

    it("8) 2nd round: Create Campaign", async function() {
      
      const vestings = [{ percent: ethers.utils.parseEther("0.25"), timestamp: (3600 * 24) }, { percent: ethers.utils.parseEther("0.5"), timestamp: (2 * (3600 * 24)) }, { percent: ethers.utils.parseEther("1"), timestamp: (3 * (3600 * 24)) }];
      const blockTimestamp1 = ((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp);
      await ido.connect(owner).create({minAllocation: parseUnits("100", 18), maxAllocation: parseUnits("1000", 18), minGoal: parseUnits("2000", 18), maxGoal: parseUnits("4000", 18), total: 0, price: parseUnits("1", 18), startTime: blockTimestamp1 + 3600, endTime: blockTimestamp1 + 13 * 3600, acquireAddress: token.address, rewardAddress: fail.address, acquireDecimals: 18, rewardDecimals: 18, status: 0}, vestings);
    
    });

    it("9) 2nd round: After 1 hour join with customer", async function() {
      
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("0", 18));

      await ido.connect(addr1).join(1, parseUnits("2000", 18));

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("1000", 18));

    });

    it("10) 2nd round: After 12 hours approve and try to claim", async function() {

      await ethers.provider.send("evm_increaseTime", [3600 * 12]);
      await ethers.provider.send("evm_mine", []);

      await reward.connect(owner).mint(ido.address, parseUnits("4000", 18));

      await ido.connect(owner).approve(1);

      await expect(ido.connect(addr1).claim(1)).to.be.revertedWith("This campaign already not claiming");

    });

    it("11) 2nd round: Refund tokens", async function() {

      expect(await token.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("0", 18));
      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("1000", 18));
      
      await ido.connect(addr1).refund(1);

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("0", 18));
      expect(await token.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("1000", 18));

    });

    it("12) 3rd round: Create Campaign", async function() {
      
      const vestings = [{ percent: ethers.utils.parseEther("0.25"), timestamp: (3600 * 24) }, { percent: ethers.utils.parseEther("0.5"), timestamp: (2 * (3600 * 24)) }, { percent: ethers.utils.parseEther("1"), timestamp: (3 * (3600 * 24)) }];
      const blockTimestamp = ((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp);
      await ido.connect(owner).create({minAllocation: parseUnits("100", 18), maxAllocation: parseUnits("1000", 18), minGoal: parseUnits("2000", 18), maxGoal: parseUnits("4000", 18), total: 0, price: parseUnits("5", 17), startTime: blockTimestamp + 3600, endTime: blockTimestamp + 13 * 3600, acquireAddress: token.address, rewardAddress: reward2.address, acquireDecimals: 18, rewardDecimals: 17, status: 0}, vestings);
    
    });

    it("13) 3rd round: Try to join", async function() {
      await expect(ido.connect(addr1).join(2, parseUnits("1000", 18))).to.be.revertedWith("Not right time to join this campaign");
    });

    it("14) 3rd round: After 1 hour join with customers", async function() {
      
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("0", 18));

      await ido.connect(addr1).join(2, parseUnits("2000", 18));

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("1000", 18));

      await ido.connect(addr2).join(2, parseUnits("500", 18));
      await ido.connect(addr2).join(2, parseUnits("750", 18));

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("2000", 18));

      await ido.connect(addr3).join(2, parseUnits("1000", 18));
      await expect(ido.connect(addr3).join(2, parseUnits("1000", 18))).to.be.revertedWith("User have max allocation");
      
      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("3000", 18));
      
      await ido.connect(addr4).join(2, parseUnits("1000", 18));

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("4000", 18));

      await expect(ido.connect(owner).join(2, parseUnits("1000", 18))).to.be.revertedWith("Goal amount already collected");

    });

    it("15) 3rd round: After 10 hours try to claim and after refund, also try to approve", async function() {

      await ethers.provider.send("evm_increaseTime", [3600 * 10]);
      await ethers.provider.send("evm_mine", []);

      await expect(ido.connect(addr1).claim(2)).to.be.revertedWith("This campaign already not claiming");
      await expect(ido.connect(addr1).refund(2)).to.be.revertedWith("This campaign already not refunding");

      await expect(ido.connect(owner).approve(2)).to.be.revertedWith("Too early for approve");

    });

    it("16) 3rd round: After 12 hours approve, try approve again and try to refund", async function() {

      await ethers.provider.send("evm_increaseTime", [3600 * 2]);
      await ethers.provider.send("evm_mine", []);

      await reward2.connect(owner).mint(ido.address, parseUnits("80000", 18));

      await ido.connect(owner).approve(2);

      expect(await token.connect(owner).balanceOf(ido.address)).to.equal(parseUnits("0", 18));
      await expect(ido.connect(owner).approve(2)).to.be.revertedWith("Not actual campaign");

      await expect(ido.connect(addr1).refund(2)).to.be.revertedWith("This campaign already not refunding");

    });

    it("17) 3rd round: Claim and after one more hour claim again", async function() {

      expect(await reward2.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("0", 18));
      console.log(2);
      await expect(ido.connect(addr1).claim(2)).to.be.revertedWith("Already nothing to claim");

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);

      await ido.connect(addr1).claim(2);

      console.log(2);

      expect(await reward2.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("5000", 18));

      await expect(ido.connect(addr1).claim(2)).to.be.revertedWith("Already nothing to claim");
    

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);

      await ido.connect(addr1).claim(2);

      expect(await reward2.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("10000", 18));
    
      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);

      await ido.connect(addr1).claim(2);

      expect(await reward2.connect(owner).balanceOf(addr1.address)).to.equal(parseUnits("20000", 18));

      await expect(ido.connect(addr1).claim(2)).to.be.revertedWith("All sum already claimed");

    });


  });


});
