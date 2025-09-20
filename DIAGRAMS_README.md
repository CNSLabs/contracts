# CNS Contract Architecture Diagrams

This document contains Mermaid diagrams that visualize the CNS token sale system architecture and relationships.

## 📁 Available Diagrams

### 1. **CNS_Architecture.mmd** - High-Level Architecture
Shows the main contract relationships and user interactions at a high level.

### 2. **CNS_Interactions.mmd** - Detailed Interactions  
Shows specific data flows and contract interactions, including bridge operations.

### 3. **CNS_User_Journey.mmd** - User Journey
Shows the complete user experience from NFT purchase to token acquisition.

### 4. **CNS_Contract_Hierarchy.mmd** - Inheritance Hierarchy
Shows the inheritance relationships between contracts and OpenZeppelin base contracts.

## 🛠️ How to View the Diagrams

### Online Tools (Recommended)
1. **Mermaid Live Editor**: https://mermaid.live/
   - Copy the contents of any `.mmd` file
   - Paste into the editor
   - View interactive diagram

2. **GitHub** (if diagrams are in a repo)
   - GitHub automatically renders Mermaid diagrams in Markdown files
   - Create a `.md` file with the diagram code

3. **VS Code Extension**
   - Install "Markdown Preview Mermaid Support" extension
   - Open any `.mmd` file to see rendered diagram

### Desktop Tools
1. **Typora** (Markdown Editor)
   - Supports Mermaid diagrams natively

2. **Mark Text** (Markdown Editor)
   - Built-in Mermaid support

3. **Obsidian** (Note-taking app)
   - Install Mermaid plugin

## 📊 Architecture Overview

### Core Components

#### **Token Layer**
- `CNSTokenL1`: L1 canonical ERC-20 token with bridge functionality
- `CNSTokenL2`: L2 bridged token with locking mechanisms

#### **Access Control Layer**  
- `CNSAccessNFT`: 3-tier NFT system (Tier 1, 2, 3 priority levels)
- `CNSTierProgression`: Time-based tier progression management
- `CNSAccessControl`: Integration layer combining NFT + time controls

#### **Sale Layer**
- `CNSTokenSale`: Main token sale contract with NFT-gated access

### Key Relationships

1. **L1/L2 Bridge**: Tokens can be bridged between layers
2. **NFT + Time Gating**: Access requires appropriate NFT tier during correct time phase
3. **Administrative Control**: Owner can configure all aspects of the system
4. **User Journey**: Clean flow from NFT purchase to token acquisition

## 🎯 Design Principles

### Security
- Uses OpenZeppelin contracts for battle-tested security
- Multiple access control layers
- Emergency pause functionality
- Reentrancy protection

### Scalability  
- L2 deployment for lower gas costs
- Tiered access system for controlled participation
- Time-based progression prevents gas wars

### User Experience
- Clear priority system (Tier 1 → Tier 2 → Tier 3)
- Transparent time-based access
- Multiple purchase methods
- Bridge functionality for flexibility

## 🔗 Integration Points

- **L1 Bridge**: Connects to external bridge contracts
- **L2 Ecosystem**: Integrates with L2 infrastructure  
- **NFT Standards**: Compatible with ERC-721 standards
- **Token Standards**: Full ERC-20 compatibility

## 📈 Usage Statistics

The diagrams help visualize:
- **6 main contracts** with clear relationships
- **3-tier access system** with time progression
- **Cross-layer functionality** (L1 ↔ L2)
- **Multi-phase sale process** with NFT gating
