# DC2S: Dendritic Cross-Compartmental Stellar Sparsing

**DC2S v3 (Dendritic Cross-Compartmental Stellar Sparsing)** is a tokenless neuromorphic Spiking Neural Network (SNN) architecture featuring hierarchical multi-compartmental stellate neurons, 15-state Mixture of Dendritic Experts (MoDE) dynamic routing, and Adaptive Leaky Integrate-and-Fire (ALIF) somas. It enables ultra-sparse (0.25%), continuous attractor dynamics and online three-factor plasticity for real-time, low-latency embodied cognition on standard CPU hardware.

---

## Architectural Highlights

* **Tokenless & Continuous:** Eliminates discrete tokenization and static matrix multiplications. Information is processed as continuous spatio-temporal spike trains directly mapped to bytes.
* **Hierarchical Dendritic Tree:** Structured binary dendritic cascade per neuron: 32 paired headless coincidence detectors $\rightarrow$ 16 secondary dendrites $\rightarrow$ 8 primary branches $\rightarrow$ ALIF soma.
* **15-State MoDE (Mixture of Dendritic Experts):** Local structural multiplexing featuring dynamic 2:1 bypasses governed by disinhibitory microcircuits (VIP+ / SOM+ / SST+), altering physical dendritic pathways in sub-millisecond regimes.
* **Ultra-Sparse Execution:** Strict **0.25% runtime sparsity** constrained by 2D Moore neighborhoods (9 functional cells per micro-cluster).
* **Hardware-Aligned (Data-Oriented Design):** Implemented in **Odin** for host CPU RAM. Each neuron occupies exactly **256 Bytes** (perfectly aligned to 4 $\times$ 64-byte cache lines), keeping active wavefronts entirely inside L2/L3 CPU cache.
* **Cognitive Dynamics:** Two-wave predictive settlement (Wave 1 feedforward sweep + Wave 2 recurrent top-down convergence + Wave 3 residual consolidation).
* **Tri-Phasic Offline Sleep:** Synaptic maintenance and homeostatic downscaling through three explicit phases: *Visualization* (replay) $\rightarrow$ *Consolidation* (Cognitive RAG & synaptic tagging) $\rightarrow$ *Cryogenesis* (standby freeze).

---

## Computational Metrics: PU & SPU Foundations

DC2S rejects traditional FLOPS and simplistic SOPS (Synaptic Operations Per Second) in favor of in-memory structural processing units:

### 1. Processing Units (PU)
Measures the baseline linear integration and coincidence detection across the primary dendritic trunks:

$$\text{PU} = \frac{\text{Synaptic Connections (128)} \times \text{Primary Dendritic Trees (8)}}{\text{Normalization Divisor (32)}} = \mathbf{32 \text{ PU / neuron}}$$

* *The normalization divisor (32)* corresponds to the 32 paired headless coincidence detector inputs ($128 / 32 = 4$ direct afferent axons per head).

### 2. Sub-Processing Units (SPU)
Integrates the dynamic structural multiplexing capacity of the 15-state MoDE bypasses over the primary trees:

$$\text{SPU} = \text{PU} \times \left( \frac{\text{MoDE Variants (16)}}{\text{Primary Trees (8)}} \right) = 32 \times 2 = \mathbf{64 \text{ SPU / neuron}}$$

* *The 16/8 ratio (= 2)* mathematically reflects the physical **2:1 compression ratio** of the MoDE bypass mechanism.

---

## Unified LLM Parameter Equivalence ($278\times$)

Because an SPU is an active, stateful, in-memory computing node executing across time, **1 SPU is not equivalent to a single static scalar float**. 

The unified equivalence factor (**$278\times$**) is derived from three physical dimensions of runtime compute density:

$$\mathbf{1 \text{ SPU}} \approx \underbrace{18 \text{ temporal relaxation steps}}_{\text{Temporal Depth}} \times \underbrace{5 \text{ equivalent MLP layers}}_{\text{Dendritic Non-linearity}} \times \underbrace{3.09 \text{ active MoDE paths}}_{\text{Dynamic Routing}} \approx \mathbf{278 \text{ Equivalent Static Parameters}}$$


---

## Authors & Credits

* **Principal Architect & Lead Designer:** **Teufel**  
  *Conceived the theoretical framework, biophysical mechanisms, mathematical formulations, structural design, and core systems architecture.*
* **Theoretical & Conceptual Brainstorming Assistant:** **Gemini 3.8 Flash**  
  *Served strictly as a sounding board and conceptual brainstorming partner for theoretical validation. Did not author or implement source code.*

---

## Contribution Policy (Strictly Closed Development)

**This repository is a strictly solo-developed research project.**

* **No external contributions will be accepted or reviewed.**
* Do not submit pull requests, open external branches, or offer code/architecture assistance.
* Unsolicited pull requests, feature proposals, and architectural reviews will be closed immediately without review. 
* All design, implementation, benchmarking, and evolution of DC2S-V3 will be conducted exclusively by the Principal Architect (**Teufel**).

---

## Disclaimer of Liability & Warranty

**THE SOFTWARE AND ARCHITECTURAL SPECIFICATIONS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.**

In no event shall the author (**Teufel**) be held liable for any claim, damages, memory corruption, execution faults, deadlocks, hardware stress, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software, experimental prototypes, or new code generated across this repository's development cycles. Run, compile, and evaluate at your own risk.

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for full details.
