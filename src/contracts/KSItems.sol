// SPDX-License-Identifier: MIT
/*
 /$$   /$$ /$$$$$$$$ /$$   /$$  /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$  /$$$$$$$$      
| $$  /$$/| $$_____/| $$  /$$/ /$$__  $$| $$__  $$ /$$__  $$ /$$__  $$| $$_____/      
| $$ /$$/ | $$      | $$ /$$/ | $$  \__/| $$  \ $$| $$  \ $$| $$  \__/| $$            
| $$$$$/  | $$$$$   | $$$$$/  |  $$$$$$ | $$$$$$$/| $$$$$$$$| $$      | $$$$$         
| $$  $$  | $$__/   | $$  $$   \____  $$| $$____/ | $$__  $$| $$      | $$__/         
| $$\  $$ | $$      | $$\  $$  /$$  \ $$| $$      | $$  | $$| $$    $$| $$            
| $$ \  $$| $$$$$$$$| $$ \  $$|  $$$$$$/| $$      | $$  | $$|  $$$$$$/| $$$$$$$$      
|__/  \__/|________/|__/  \__/ \______/ |__/      |__/  |__/ \______/ |________/      
*/
pragma solidity ^0.8.27;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ERC1155Burnable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import {ERC1155Pausable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {ERC2981} from "solady/src/tokens/ERC2981.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title KSItems
/// @notice This contract allows for:
/// - Creation of multiple types of in-game items, each with its own ID
/// - Minting multiple copies of each item
/// - Tracking the total supply of each item
/// - Setting metadata (images, descriptions) for each item
/// - Burning items when needed
contract KSItems is
    ERC1155,
    Ownable,
    ERC1155Pausable,
    ERC1155Burnable,
    ERC1155Supply,
    ERC1155URIStorage,
    ERC1155Holder,
    ERC2981
{
    /// @dev Custom error for array length mismatch
    error ArrayLengthMismatch();
    /// @dev Custom error for zero address input
    error ZeroAddress();
    /// @dev Custom error for zero amount input
    error ZeroAmount();
    /// @dev Custom error for invalid royalty percentage
    error InvalidRoyaltyPercentage();

    /// @dev Token name for better integration with wallets/marketplaces
    string public name;
    /// @dev Token symbol for better integration with wallets/marketplaces
    string public symbol;

    /// @dev Maximum royalty percentage (5% = 500 basis points)
    uint256 private constant MAX_2981_PERCENTAGE = 500;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor() ERC1155("https://files.memetimestudios.xyz/metadata/") {
        _initializeOwner(msg.sender);

        name = unicode"KS Items";
        symbol = unicode"KSIs";

        _setDefaultRoyalty(msg.sender, 0); ///start @0%, 500 bps = 5%
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      MINTING FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Creates new copies of a specific game item
    /// @dev Only the owner can create new items
    /// This function is used to add new items to players' inventories
    /// @param account The address that will receive the new items
    /// @param id The ID of the game item to create
    /// @param amount How many copies of the item to create
    function mint(
        address account,
        uint256 id,
        uint256 amount
    ) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();

        _mint(account, id, amount, "");

        emit TokenMinted(account, id, amount, msg.sender);
    }

    /// @notice Creates multiple different game items at once
    /// @dev Only the owner can create new items
    /// This is a more efficient way to mint multiple types of items at once
    /// @param to The address that will receive the items
    /// @param ids Array of item IDs to create
    /// @param amounts Array of amounts for each item ID
    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (ids.length != amounts.length) revert ArrayLengthMismatch();

        _mintBatch(to, ids, amounts, "");

        emit TokenBatchMinted(to, ids, amounts, msg.sender);
    }

    /// @notice Drops tokens to multiple recipients
    /// @dev Only the owner can gift tokens
    /// Supports both uniform and variable distribution:
    /// - If amounts.length == 1: gives amounts[0] to all recipients
    /// - If amounts.length == recipients.length: gives amounts[i] to recipients[i]
    /// @param recipients Array of addresses to receive tokens
    /// @param id Token ID to mint
    /// @param amounts Array of amounts - length 1 for uniform, length=recipients for variable
    function gift(
        address[] calldata recipients,
        uint256 id,
        uint256[] calldata amounts
    ) external onlyOwner {
        uint256 recipientLength = recipients.length;
        uint256 amountLength = amounts.length;

        if (amountLength != 1 && amountLength != recipientLength) {
            revert ArrayLengthMismatch();
        }

        bool isUniform = amountLength == 1;
        uint256 uniformAmount = isUniform ? amounts[0] : 0;
        for (uint256 i; i < recipientLength; ) {
            address recipient = recipients[i];
            if (recipient == address(0)) revert ZeroAddress();

            uint256 mintAmount = isUniform ? uniformAmount : amounts[i];
            _mint(recipient, id, mintAmount, "");
            unchecked {
                ++i;
            }
        }

        if (isUniform) {
            emit TokenGifted(id, recipients, uniformAmount, msg.sender);
        } else {
            emit TokenVariableGifted(id, recipients, amounts, msg.sender);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      URI FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the token-specific URI for a specific game item
    /// @dev Only the owner can set token URIs
    /// This allows setting different images and descriptions for each item type
    /// This overrides the base URI for this specific token
    /// @param tokenId The ID of the game item
    /// @param tokenURI The URI pointing to the item's metadata
    function setTokenURI(uint256 tokenId, string memory tokenURI)
        public
        onlyOwner
    {
        super._setURI(tokenId, tokenURI);
        emit TokenURISet(tokenId, tokenURI);
    }

    /// @notice Sets the metadata URIs for multiple game items in a single transaction
    /// @dev Only the owner can set token URIs
    /// This is more gas-efficient than setting URIs individually
    /// @param tokenIds Array of token IDs
    /// @param tokenURIs Array of URIs pointing to each item's metadata
    function setBatchTokenURI(
        uint256[] memory tokenIds,
        string[] memory tokenURIs
    ) public onlyOwner {
        if (tokenIds.length != tokenURIs.length) revert ArrayLengthMismatch();

        uint256 length = tokenIds.length;
        for (uint256 i; i < length; ) {
            super._setURI(tokenIds[i], tokenURIs[i]);
            emit TokenURISet(tokenIds[i], tokenURIs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   UTILITY FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets the current base URI
    /// @return The base URI string
    function getBaseURI() external view returns (string memory) {
        return super.uri(0);
    }

    /// @notice Checks if contract is paused
    /// @return True if paused
    function isPaused() external view returns (bool) {
        return paused();
    }

    /// @notice Gets balance of multiple accounts for a single token
    /// @param accounts Array of addresses to query
    /// @param id Token ID to query
    /// @return balances Array of balances
    function balanceOfBatch(address[] calldata accounts, uint256 id)
        external
        view
        returns (uint256[] memory balances)
    {
        uint256 length = accounts.length;
        balances = new uint256[](length);

        for (uint256 i; i < length; ) {
            balances[i] = balanceOf(accounts[i], id);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Gets total supplies for multiple token IDs
    /// @param ids Array of token IDs to query
    /// @return supplies Array of total supplies
    function totalSupplyBatch(uint256[] calldata ids)
        external
        view
        returns (uint256[] memory supplies)
    {
        uint256 length = ids.length;
        supplies = new uint256[](length);

        for (uint256 i; i < length; ) {
            supplies[i] = totalSupply(ids[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Checks if multiple tokens exist
    /// @param tokenIds Array of token IDs to check
    /// @return existsArray Array of existence booleans
    function existsBatch(uint256[] calldata tokenIds)
        external
        view
        returns (bool[] memory existsArray)
    {
        uint256 length = tokenIds.length;
        existsArray = new bool[](length);

        for (uint256 i; i < length; ) {
            existsArray[i] = totalSupply(tokenIds[i]) > 0;
            unchecked {
                ++i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    VIEW FUNCTIONS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets the metadata URI for a specific game item
    /// @dev Returns token-specific URI if set via setTokenURI(),
    /// otherwise returns baseURI + tokenId + ".json"
    /// @param tokenId The ID of the game item
    /// @return The URI string pointing to the item's metadata
    function uri(uint256 tokenId)
        public
        view
        override(ERC1155, ERC1155URIStorage)
        returns (string memory)
    {
        string memory customURI = super.uri(tokenId);
        string memory currentBaseURI = super.uri(0);
        /// custom URI is different from base URI, return custom URI
        if (
            bytes(customURI).length > 0 &&
            keccak256(bytes(customURI)) != keccak256(bytes(currentBaseURI))
        ) {
            return customURI;
        }
        /// construct: baseURI + tokenId + ".json"
        return
            string(
                abi.encodePacked(currentBaseURI, _toString(tokenId), ".json")
            );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the base URI for all token metadata
    /// @dev Only the owner can call this function
    /// The URI is used as a fallback for tokens that don't have a specific URI set
    /// @param newuri The new base URI to set
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
        emit BaseURISet(newuri);
    }

    /// @notice Pauses all token transfers and operations
    /// @dev Only the owner can call this function
    /// This is a safety feature for emergency situations
    function pause() public onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /// @notice Unpauses the contract, allowing transfers again
    /// @dev Only the owner can call this function
    /// Use this after resolving any issues that required pausing
    function unpause() public onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    /// @notice Sets the default royalty that applies to all tokens
    /// @dev Only the owner can set royalties
    /// Maximum royalty is 5% (500 basis points)
    /// @param receiver Address that will receive royalty payments
    /// @param feeNumerator Royalty percentage in basis points (e.g., 500 = 5%)
    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        external
        onlyOwner
    {
        if (receiver == address(0)) revert ZeroAddress();
        if (feeNumerator > MAX_2981_PERCENTAGE)
            revert InvalidRoyaltyPercentage();

        _setDefaultRoyalty(receiver, feeNumerator);
        emit DefaultRoyaltySet(receiver, feeNumerator);
    }

    /// @notice Sets royalty for a specific token (overrides default)
    /// @dev Only the owner can set royalties
    /// Maximum royalty is 5% (500 basis points)
    /// @param tokenId Token ID to set royalty for
    /// @param receiver Address that will receive royalty payments for this token
    /// @param feeNumerator Royalty percentage in basis points (e.g., 500 = 5%)
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        if (feeNumerator > MAX_2981_PERCENTAGE)
            revert InvalidRoyaltyPercentage();

        _setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit TokenRoyaltySet(tokenId, receiver, feeNumerator);
    }

    /// @notice Recovery withdrawal of ETH or ERC20 tokens to owner
    /// @param token Address of ERC20 token, or address(0) for ETH
    function recover(address token) external onlyOwner {
        if (token == address(0)) {
            uint256 ethBalance = address(this).balance;
            if (ethBalance > 0) {
                payable(owner()).transfer(ethBalance);
            }
        } else {
            IERC20 tokenContract = IERC20(token);
            uint256 tokenBalance = tokenContract.balanceOf(address(this));
            if (tokenBalance > 0) {
                tokenContract.transfer(owner(), tokenBalance);
            }
        }
    }

    /// @dev Internal function to convert uint256 to string
    /// @param value The number to convert
    /// @return The string representation
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /// @notice Checks if the contract supports a specific interface
    /// @dev This function is necessary to properly handle both being an ERC1155 token
    /// and being able to receive ERC1155 tokens, plus royalty support
    /// @param interfaceId The interface identifier to check
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(ERC1155, ERC1155Holder, ERC2981)
        returns (bool result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let s := shr(224, interfaceId)
            result := or(
                or(
                    or(
                        or(eq(s, 0x01ffc9a7), eq(s, 0xd9b67a26)),
                        eq(s, 0x0e89341c)
                    ),
                    eq(s, 0x4e2312e0)
                ),
                eq(s, 0x2a55205a)
            )
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   INTERNAL FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Internal function that handles token transfers
    /// @dev This function is overridden to ensure that:
    /// - The contract respects the pause status
    /// - The supply of each token is properly tracked
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Pausable, ERC1155Supply) {
        super._update(from, to, ids, values);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when tokens are minted to a single recipient
    /// @param to The recipient address
    /// @param tokenId The token ID that was minted
    /// @param amount The amount minted
    /// @param minter The address that initiated the mint
    event TokenMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint256 amount,
        address indexed minter
    );

    /// @dev Emitted when multiple token types are minted to a single recipient
    /// @param to The recipient address
    /// @param tokenIds Array of token IDs that were minted
    /// @param amounts Array of amounts minted for each token ID
    /// @param minter The address that initiated the mint
    event TokenBatchMinted(
        address indexed to,
        uint256[] tokenIds,
        uint256[] amounts,
        address indexed minter
    );

    /// @dev Emitted when tokens are gifted to multiple recipients
    /// @param tokenId The token ID that was gifted
    /// @param recipients Array of recipient addresses
    /// @param amountPerRecipient Amount each recipient received
    /// @param minter The address that initiated the gift
    event TokenGifted(
        uint256 indexed tokenId,
        address[] recipients,
        uint256 amountPerRecipient,
        address indexed minter
    );

    /// @dev Emitted when tokens are giftped with variable amounts
    /// @param tokenId The token ID that was giftped
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts each recipient received
    /// @param minter The address that initiated the gift
    event TokenVariableGifted(
        uint256 indexed tokenId,
        address[] recipients,
        uint256[] amounts,
        address indexed minter
    );

    /// @dev Emitted when the contract is paused
    /// @param account The address that paused the contract
    event ContractPaused(address indexed account);

    /// @dev Emitted when the contract is unpaused
    /// @param account The address that unpaused the contract
    event ContractUnpaused(address indexed account);

    /// @dev Emitted when the URI for a token is set
    /// @param tokenId The ID of the token
    /// @param tokenURI The new URI for the token
    event TokenURISet(uint256 indexed tokenId, string tokenURI);

    /// @dev Emitted when the base URI is set
    /// @param baseURI The new base URI
    event BaseURISet(string baseURI);

    /// @dev Emitted when default royalty is set
    /// @param receiver The royalty receiver address
    /// @param feeNumerator The royalty fee (in basis points, out of 10000)
    event DefaultRoyaltySet(address indexed receiver, uint256 feeNumerator);

    /// @dev Emitted when token-specific royalty is set
    /// @param tokenId The token ID
    /// @param receiver The royalty receiver address
    /// @param feeNumerator The royalty fee (in basis points, out of 10000)
    event TokenRoyaltySet(
        uint256 indexed tokenId,
        address indexed receiver,
        uint256 feeNumerator
    );
}
