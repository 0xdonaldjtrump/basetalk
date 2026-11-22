const solc=require("solc"),fs=require("fs"),ganache=require("ganache"),{ethers}=require("ethers");
const b=JSON.parse(fs.readFileSync("build.json"));
const mo=JSON.parse(solc.compile(JSON.stringify({language:"Solidity",sources:{"M.sol":{content:fs.readFileSync("test/MockFeed.sol","utf8")}},settings:{evmVersion:"paris",outputSelection:{"*":{"*":["abi","evm.bytecode.object","evm.deployedBytecode.object"]}}}}))).contracts["M.sol"].MockFeed;
const assert=(c,m)=>{if(!c)throw new Error("FAIL "+m);console.log("ok -",m)};
(async()=>{
 const g=ganache.provider({logging:{quiet:true},chain:{hardfork:"shanghai"},wallet:{totalAccounts:4,defaultBalance:1000}});
 const p=new ethers.BrowserProvider(g);
 const [o,a,bb,c]=await Promise.all([0,1,2,3].map(i=>p.getSigner(i)));
 const F=new ethers.ContractFactory(b.abi,b.bytecode,o);
 const t=await F.deploy(); await t.waitForDeployment();
 // no feed code at hardcoded address -> fallback
 assert((await t.weiPerUsd())==333333333333333n,"fallback when feed missing");
 // install mock at feed address
 const FEED="0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70";
 await g.request({method:"evm_setAccountCode",params:[FEED,"0x"+mo.evm.deployedBytecode.object]});
 // storage slot0 answer
 await g.request({method:"evm_setAccountStorageAt",params:[FEED,ethers.toBeHex(0,32),ethers.toBeHex(250000000000n,32)]});
 const wpu=await t.weiPerUsd(); assert(wpu==ethers.parseEther("1")/2500n,"oracle price $2500 -> "+wpu);
 const reg=await t.registerFeeWei(), mf=await t.messageFeeWei();
 assert(reg==wpu && mf==wpu/100n,"fees $1 & $0.01");
 const bal=async x=>BigInt(await g.request({method:"eth_getBalance",params:[x,"latest"]}));const ob0=await bal(await o.getAddress());
 await (await t.connect(a).register("Ania",{value:reg})).wait();
 await (await t.connect(bb).register("Bartek",{value:reg})).wait();
 const ob1=await bal(await o.getAddress());
 assert(ob1-ob0==2n*reg,"fees forwarded to owner");
 try{await t.connect(a).register("x",{value:reg});assert(false,"dup")}catch(e){assert(/AlreadyRegistered|revert/.test(e.message),"no double register")}
 try{await t.connect(c).register("Cz",{value:reg-1n});assert(false,"low")}catch(e){assert(true,"low fee rejected")}
 try{await t.connect(c).sendMessage(1,"hi",{value:mf});assert(false,"unreg")}catch(e){assert(true,"unregistered cannot send")}
 await (await t.connect(a).sendMessage(2,"Czesc Bartek! 😀",{value:mf})).wait();
 await (await t.connect(bb).sendMessage(1,"Siema!",{value:mf})).wait();
 await (await t.connect(a).sendMessage(2,"Co tam?",{value:mf*102n/100n})).wait();
 const [msgs,ids]=await t.getConversation(2,1,0,50);
 assert(msgs.length==3 && msgs[0].text=="Czesc Bartek! 😀" && msgs[1].from==2n,"conversation stored");
 assert((await t.conversationLength(1,2))==3n,"convo length");
 assert((await t.getPartners(1)).length==1,"partners");
 assert((await t.inboxCount(2))==2n,"inbox count");
 await (await t.connect(a).setStatus(2,"zaraz wracam",{gasLimit:300000})).wait();
 const u=await t.getUser(1); assert(u.status==2n&&u.statusText=="zaraz wracam"&&u.nick=="Ania","status");
 await (await t.connect(a).addContact(2)).wait(); await (await t.connect(a).addContact(2)).wait();
 assert((await t.getContacts(1)).length==1,"contact add idempotent");
 await (await t.connect(a).removeContact(2)).wait(); assert((await t.getContacts(1)).length==0,"contact removed");
 await (await t.connect(bb).setBlocked(1,true)).wait();
 try{await t.connect(a).sendMessage(2,"spam",{value:mf});assert(false,"blk")}catch(e){assert(true,"blocked sender rejected")}
 const ch=await t.getChats(1); assert(ch[0].length==1&&ch[0][0]==2n&&ch[1][0]==3n&&ch[2][0]>0n,"getChats");
 const dir=await t.getUsers(1,50); assert(dir.length==2 && dir[1].nick=="Bartek","directory");
 // stale oracle -> fallback
 await g.request({method:"evm_setAccountStorageAt",params:[FEED,ethers.toBeHex(1,32),ethers.toBeHex(7*3600,32)]});
 assert((await t.weiPerUsd())==333333333333333n,"stale -> fallback");
 try{await t.connect(a).setFees(1,1);assert(false,"own")}catch(e){assert(true,"only owner setFees")}
 await (await t.setFees(2000000,100)).wait(); assert((await t.messageFeeMicroUsd())==100n,"owner setFees (0.01 cent)");
 const s=await t.stats(); console.log("stats",s.map(String));
 const rc=await (await t.connect(bb).sendMessage(1,"x".repeat(300),{value:await t.messageFeeWei()})).wait();
 console.log("gas 300-char msg:",rc.gasUsed.toString());
 try{await t.connect(bb).sendMessage(1,"x".repeat(301),{value:ethers.parseEther("1")});assert(false,"len")}catch(e){assert(true,"too long rejected")}
 await (await t.setFallbackWeiPerUsd(5n*10n**14n,true)).wait(); assert((await t.weiPerUsd())==5n*10n**14n,"fixed price switch");
 await (await t.setFallbackWeiPerUsd(333333333333333n,false)).wait();
 await g.request({method:"evm_setAccountCode",params:[FEED,"0xfe"]});
 assert((await t.weiPerUsd())==333333333333333n,"broken oracle -> fallback (no revert)");
 console.log("ALL PASSED");
})().catch(e=>{console.error(e.message);process.exit(1)});
