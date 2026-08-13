# UART-Driven 4×4 Crossbar Packet Switch

A Verilog RTL implementation of a **4×4 Crossbar Packet Switch** developed as the final project for the **NTI FPGA Flow & RTL Design with Verilog Training Program**.

## Project Overview

The switch routes **64-bit packets** between four input and four output ports based on the packet destination address.

### Main Modules

- FIFO Queues
- Header Parser
- Routing Table
- Round-Robin Arbiter
- 4×4 Crossbar
- UART RX/TX and Packet Bridges

## Packet Format

Each packet is **64 bits**:

- 16-bit header
- 48-bit payload

The destination address determines the output port through the routing table.

## Verification

The packet-switch RTL was verified using **Verilog testbenches and ModelSim**, covering routing, arbitration, back-pressure, and multiple-port scenarios.

## Tools

- Verilog-2005
- ModelSim
- RTL Design

## Team

- Mohamed Ahmed Mahmoud
- Mariam Badawy Helmy
- Sama Mohamed Ahmed
- Mahmoud Mostafa Elsayed
- Abanoub Ashraf Saneed

**Supervisor:** Eng. Mohamed Salah
