// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "dss-test/DssTest.sol";

import { NstPsmWrapper } from "src/NstPsmWrapper.sol";
import { MockLitePsm }   from "test/mocks/MockLitePsm.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface TokenLike {
    function approve(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
}

interface VatLike {
    function can(address, address) external view returns (uint256);
    function cage() external;
}

contract NstPsmWrapperTest is DssTest {
    ChainlogLike constant chainlog = ChainlogLike(address(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F));

    TokenLike     usdc;
    TokenLike     nst;
    TokenLike     dai;
    MockLitePsm   litePsm;
    NstPsmWrapper wrapper;
    address       daiJoin;
    address       nstJoin;
    address       vat;
    address       pauseProxy;

    bytes32 constant ilk    = "ILK";
    address constant usr    = address(0x123);
    address constant pocket = address(0x456);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        usdc       = TokenLike(chainlog.getAddress("USDC"));
        nst        = TokenLike(chainlog.getAddress("NST"));
        dai        = TokenLike(chainlog.getAddress("MCD_DAI"));
        daiJoin    = chainlog.getAddress("MCD_JOIN_DAI");
        nstJoin    = chainlog.getAddress("NST_JOIN");
        vat        = chainlog.getAddress("MCD_VAT");
        pauseProxy = chainlog.getAddress("MCD_PAUSE_PROXY");

        litePsm = new MockLitePsm(ilk, address(usdc), daiJoin, pocket);
        vm.prank(pocket); usdc.approve(address(litePsm), type(uint256).max);
        deal(address(usdc), pocket, 100_000_000 * 10 ** 6);
        deal(address(dai), address(litePsm), 100_000_000 * 10 ** 18);

        wrapper = new NstPsmWrapper(address(litePsm), nstJoin);
    }

    function testConstructor() public view {
        assertEq(address(wrapper.psm()),     address(litePsm));
        assertEq(address(wrapper.gem()),     address(usdc));
        assertEq(address(wrapper.nstJoin()), nstJoin);
        assertEq(address(wrapper.nst()),     address(nst));
        assertEq(address(wrapper.vat()),     vat);

        assertEq(wrapper.to18ConversionFactor(), 10 ** 12);

        assertEq(dai.allowance( address(wrapper), address(litePsm)), type(uint256).max);
        assertEq(usdc.allowance(address(wrapper), address(litePsm)), type(uint256).max);
        assertEq(dai.allowance( address(wrapper),          daiJoin), type(uint256).max);
        assertEq(nst.allowance( address(wrapper),          nstJoin), type(uint256).max);

        assertEq(VatLike(vat).can(address(wrapper), daiJoin), 1);
        assertEq(VatLike(vat).can(address(wrapper), nstJoin), 1);
    }

    function testGetters() public {
        litePsm.file("vow",  address(0xaaa));
        litePsm.file("tin",  12);
        litePsm.file("tout", 34);
        litePsm.file("buf",  56);

        assertEq(wrapper.ilk(),     ilk);
        assertEq(wrapper.vow(),     address(0xaaa));
        assertEq(wrapper.dai(),     address(nst));
        assertEq(wrapper.gemJoin(), address(wrapper));
        assertEq(wrapper.pocket(),  pocket);
        assertEq(wrapper.tin(),     12);
        assertEq(wrapper.tout(),    34);
        assertEq(wrapper.buf(),     56);
        assertEq(wrapper.dec(),     6);
        assertEq(wrapper.live(),    1);
        vm.prank(pauseProxy); VatLike(vat).cage();
        assertEq(wrapper.live(),    0);
    }

    function testSellGem() public {
        deal(address(usdc), address(this), 1000 * 10 ** 6);

        uint256 nstUsrBefore     = nst.balanceOf(usr);
        uint256 daiPsmBefore     = dai.balanceOf(address(litePsm));
        uint256 usdcSellerBefore = usdc.balanceOf(address(this));
        uint256 usdcPocketBefore = usdc.balanceOf(pocket);

        usdc.approve(address(wrapper), 1000 * 10 ** 6);
        assertEq(wrapper.sellGem(usr, 1000 * 10 ** 6), 1000 * 10 ** 18);

        assertEq(nst.balanceOf(usr),              nstUsrBefore     + 1000 * 10 ** 18);
        assertEq(dai.balanceOf(address(litePsm)), daiPsmBefore     - 1000 * 10 ** 18);
        assertEq(usdc.balanceOf(address(this)),   usdcSellerBefore - 1000 * 10 ** 6);
        assertEq(usdc.balanceOf(pocket),          usdcPocketBefore + 1000 * 10 ** 6);
        assertEq(usdc.balanceOf(address(wrapper)), 0);
        assertEq(nst.balanceOf(address(wrapper)),  0);
        assertEq(dai.balanceOf(address(wrapper)),  0);
    }

    function testSellGemWithFee() public {
        litePsm.file("tin", 1 * 10 ** 18 / 100);

        deal(address(usdc), address(this), 1000 * 10 ** 6);

        uint256 nstUsrBefore     = nst.balanceOf(usr);
        uint256 daiPsmBefore     = dai.balanceOf(address(litePsm));
        uint256 usdcSellerBefore = usdc.balanceOf(address(this));
        uint256 usdcPocketBefore = usdc.balanceOf(pocket);

        usdc.approve(address(wrapper), 1000 * 10 ** 6);
        assertEq(wrapper.sellGem(usr, 1000 * 10 ** 6), 990 * 10 ** 18);

        assertEq(nst.balanceOf(usr),              nstUsrBefore     +  990 * 10 ** 18);
        assertEq(dai.balanceOf(address(litePsm)), daiPsmBefore     -  990 * 10 ** 18);
        assertEq(usdc.balanceOf(address(this)),   usdcSellerBefore - 1000 * 10 ** 6);
        assertEq(usdc.balanceOf(pocket),          usdcPocketBefore + 1000 * 10 ** 6);
        assertEq(usdc.balanceOf(address(wrapper)), 0);
        assertEq(nst.balanceOf(address(wrapper)),  0);
        assertEq(dai.balanceOf(address(wrapper)),  0);
    }

    function testBuyGem() public {
        deal(address(nst), address(this), 1000 * 10 ** 18);

        uint256 nstBuyerBefore   = nst.balanceOf(address(this));
        uint256 daiPsmBefore     = dai.balanceOf(address(litePsm));
        uint256 usdcUsrBefore    = usdc.balanceOf(usr);
        uint256 usdcPocketBefore = usdc.balanceOf(pocket);

        nst.approve(address(wrapper), 1000 * 10 ** 18);
        assertEq(wrapper.buyGem(usr, 1000 * 10 ** 6), 1000 * 10 ** 18);

        assertEq(nst.balanceOf(address(this)),    nstBuyerBefore   - 1000 * 10 ** 18);
        assertEq(dai.balanceOf(address(litePsm)), daiPsmBefore     + 1000 * 10 ** 18);
        assertEq(usdc.balanceOf(usr),             usdcUsrBefore    + 1000 * 10 ** 6);
        assertEq(usdc.balanceOf(pocket),          usdcPocketBefore - 1000 * 10 ** 6);
        assertEq(usdc.balanceOf(address(wrapper)), 0);
        assertEq(nst.balanceOf(address(wrapper)),  0);
        assertEq(dai.balanceOf(address(wrapper)),  0);
    }

    function testBuyGemWithFee() public {
        litePsm.file("tout", 1 * 10 ** 18 / 100);

        deal(address(nst), address(this), 1010 * 10 ** 18);

        uint256 nstBuyerBefore   = nst.balanceOf(address(this));
        uint256 daiPsmBefore     = dai.balanceOf(address(litePsm));
        uint256 usdcUsrBefore    = usdc.balanceOf(usr);
        uint256 usdcPocketBefore = usdc.balanceOf(pocket);

        nst.approve(address(wrapper), 1010 * 10 ** 18);
        assertEq(wrapper.buyGem(usr, 1000 * 10 ** 6), 1010 * 10 ** 18);

        assertEq(nst.balanceOf(address(this)),    nstBuyerBefore   - 1010 * 10 ** 18);
        assertEq(dai.balanceOf(address(litePsm)), daiPsmBefore     + 1010 * 10 ** 18);
        assertEq(usdc.balanceOf(usr),             usdcUsrBefore    + 1000 * 10 ** 6);
        assertEq(usdc.balanceOf(pocket),          usdcPocketBefore - 1000 * 10 ** 6);
        assertEq(usdc.balanceOf(address(wrapper)), 0);
        assertEq(nst.balanceOf(address(wrapper)),  0);
        assertEq(dai.balanceOf(address(wrapper)),  0);
    }
}
