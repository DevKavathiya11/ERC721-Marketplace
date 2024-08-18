// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Dev721.sol";
import "./INFTMarketplace.sol";

contract NFTMarketplace is INFTMarketplace, ReentrancyGuard {
    Dev private nftContract;

    struct Listing {
        address seller;
        uint256 price;
        bool isActive;
    }

    struct Auction {
        address seller;
        uint256 startingPrice;
        uint256 endTime;
        address highestBidder;
        uint256 highestBid;
        bool isActive;
    }

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => uint256)) private bids;
    mapping(uint256 => uint256) private _salePrices;
    mapping(uint256 => bool) private _tokenExists;
    uint256[] private _tokenIds;

    constructor(address nftAddress) {
        nftContract = Dev(nftAddress);
    }

    function putNftSale(uint256 tokenId_, uint256 price_)
        external
        payable
        override
        nonReentrant
    {
        try nftContract.ownerOf(tokenId_) returns (address owner) {
            require(owner == msg.sender, "NFTMarketplace: Not the owner");
        } catch {
            revert("NFTMarketplace: Token does not exist");
        }

        require(!listings[tokenId_].isActive, "NFTMarketplace: Token already listed");
        require(
            nftContract.getApproved(tokenId_) == address(this) ||
            nftContract.isApprovedForAll(msg.sender, address(this)),
            "NFTMarketplace: Marketplace not approved"
        );
        require(!auctions[tokenId_].isActive, "NFTMarketplace: Token is in an active auction");

        listings[tokenId_] = Listing({
            seller: msg.sender,
            price: price_,
            isActive: true
        });

        if (!_tokenExists[tokenId_]) {
            _tokenIds.push(tokenId_);
            _tokenExists[tokenId_] = true;
        }

        emit Listed(tokenId_, msg.sender, price_);
    }

    function unlistNftSale(uint256 tokenId_) external override nonReentrant {
        Listing memory listing = listings[tokenId_];
        require(listing.isActive, "NFTMarketplace: Token not listed");
        require(listing.seller == msg.sender, "NFTMarketplace: Not the seller");

        delete listings[tokenId_];

        emit Unlisted(tokenId_);
    }

    function buyNft(uint256 tokenId_) external payable override nonReentrant {
        Listing memory listing = listings[tokenId_];
        require(listing.isActive, "NFTMarketplace: Token not listed");
        address seller = listing.seller;
        require(seller != msg.sender, "NFTMarketplace: Seller cannot buy their own token");
        require(msg.value >= listing.price, "NFTMarketplace: Insufficient payment");

        nftContract.transferFrom(seller, msg.sender, tokenId_);

        _salePrices[tokenId_] = listing.price;
        listings[tokenId_].isActive = false;

        payable(seller).transfer(listing.price);

        emit Purchased(tokenId_, msg.sender, listing.price);
    }

    function startAuction(
        uint256 tokenId_,
        uint256 startingPrice,
        uint256 duration
    ) external override nonReentrant {
        try nftContract.ownerOf(tokenId_) returns (address owner) {
            require(owner == msg.sender, "NFTMarketplace: Not the owner");
        } catch {
            revert("NFTMarketplace: Token does not exist");
        }

        require(!listings[tokenId_].isActive, "NFTMarketplace: NFT listed for sale");
        require(!auctions[tokenId_].isActive, "NFTMarketplace: Auction already active");
        require(
            nftContract.getApproved(tokenId_) == address(this) ||
            nftContract.isApprovedForAll(msg.sender, address(this)),
            "Marketplace: Marketplace not approved"
        );

        auctions[tokenId_] = Auction({
            seller: msg.sender,
            startingPrice: startingPrice,
            endTime: block.timestamp + duration,
            highestBidder: address(0),
            highestBid: 0,
            isActive: true
        });

        if (!_tokenExists[tokenId_]) {
            _tokenIds.push(tokenId_);
            _tokenExists[tokenId_] = true;
        }

        emit AuctionStarted(
            tokenId_,
            msg.sender,
            startingPrice,
            auctions[tokenId_].endTime
        );
    }

    function bid(uint256 tokenId_) external payable nonReentrant {
        Auction storage auction = auctions[tokenId_];
        require(auction.isActive, "NFTMarketplace: Auction not active");
        require(!listings[tokenId_].isActive, "NFTMarketplace: Token listed for sale");
        require(
            msg.value > auction.highestBid &&
            msg.value >= auction.startingPrice,
            "NFTMarketplace: Bid too low"
        );
        require(block.timestamp < auction.endTime, "NFTMarketplace: Auction ended");
        require(auction.highestBidder != msg.sender, "Marketplace: Last Bidder Can't bid again");

        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;
        bids[tokenId_][msg.sender] = msg.value;

        emit NewBid(tokenId_, msg.sender, msg.value);
    }

    function endAuction(uint256 tokenId_) external nonReentrant {
        Auction memory auction = auctions[tokenId_];
        require(auction.isActive, "NFTMarketplace: Auction not active");
        require(nftContract.ownerOf(tokenId_) != address(0), "Marketplace: Invalid tokenId");
        require(auction.seller == msg.sender, "NFTMarketplace: Not authorized");
        require(auction.highestBidder != address(0), "Marketplace: No bids placed");

        _salePrices[tokenId_] = auction.highestBid;

        nftContract.transferFrom(
            auction.seller,
            auction.highestBidder,
            tokenId_
        );

        delete listings[tokenId_];
        auction.isActive = false;
        payable(auction.seller).transfer(auction.highestBid);

        emit AuctionEnded(tokenId_, auction.highestBidder, auction.highestBid);
    }

    function cancelAuction(uint256 tokenId_) external nonReentrant {
        Auction storage auction = auctions[tokenId_];
        require(auction.isActive, "NFTMarketplace: Auction not active");
        require(auction.seller == msg.sender, "NFTMarketplace: Not the seller");

        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }


        delete listings[tokenId_];

        emit AuctionCancelled(tokenId_);
    }

    function getAllSalePricesSorted()
        external
        view
        returns (uint256[] memory sortedtokenIds, uint256[] memory sortedPrices)
    {
        uint256 totalTokens = 0;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (_salePrices[_tokenIds[i]] > 0) {
                totalTokens++;
            }
        }

        uint256[] memory tokens = new uint256[](totalTokens);
        uint256[] memory prices = new uint256[](totalTokens);
        uint256 index = 0;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (_salePrices[_tokenIds[i]] > 0) {
                tokens[index] = _tokenIds[i];
                prices[index] = _salePrices[_tokenIds[i]];
                index++;
            }
        }

        for (uint256 i = 0; i < prices.length; i++) {
            for (uint256 j = i + 1; j < prices.length; j++) {
                if (prices[i] > prices[j]) {
                    uint256 tempPrice = prices[i];
                    prices[i] = prices[j];
                    prices[j] = tempPrice;

                    uint256 tempToken = tokens[i];
                    tokens[i] = tokens[j];
                    tokens[j] = tempToken;
                }
            }
        }

        return (tokens, prices);
    }
}
