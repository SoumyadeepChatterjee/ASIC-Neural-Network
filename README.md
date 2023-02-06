# ASIC-Neural-Network
Verilog implementation of a CNN Module in a Neural Network Chip; synthesized fully in Synopsys

# Overview
Contains the design and synthesized netlist for the Convolutional layer, a ReLu Activation Function,
and a MaxPooling minimization layer. The project report details the design ideology, implementation
challenges, and final design UML with the key registers named and described.

# To Run
Copy into a fresh directory, and source your Synopsys setup files
The following command executes the Synopsys synthesis - make-debug-564-base

# Under the hood
The outputs of the design are verified against a golden model for each input configuration;
then simulator as-is runs 2 sets of inputs matrices and kernels to determine functionality.

# Result/Reports
The timing and total cell area reports provide insights into the performance metrics achieved
by this implementation.

# Improvements/Augmentations
The design, while completing with a small clock period, can be minimized by parallelizing operations
with further utilization of continuous assignment statements. Further, the decision to clearly separate 
different aspect of the data path did not yield itself to minimize area; in this vein, further
optimizations by reducing the number of Finite State Machines (FSMs) to 2 shall be pursued.
