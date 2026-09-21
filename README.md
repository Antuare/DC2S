# DC2S: Dendritic Cross-Compartmental Stellar Sparsing

**DC2S  (Dendritic Cross-Compartmental Stellar Sparsing)** is a Spiking Neural Network (SNN) architecture featuring hierarchical multi-compartmental stellate neurons, dynamic routing, and Adaptive Leaky Integrate-and-Fire (ALIF) somas. It enables ultra-sparse (0.25%), continuous attractor dynamics and online three-factor plasticity for real-time, low-latency embodied cognition on standard CPU hardware.

---

## Architectural Highlights

* **Continuous:** Information is processed as continuous spatio-temporal spike trains directly mapped to bytes.
* **Hierarchical Dendritic Tree:** Structured binary dendritic cascade per neuron: 32 paired headless coincidence detectors $\rightarrow$ 16 secondary dendrites $\rightarrow$ 8 primary branches $\rightarrow$ ALIF soma.
* **Ultra-Sparse Execution:** Strict **0.25% runtime sparsity** constrained by 2D Moore neighborhoods (9 functional cells per micro-cluster).
* **Hardware-Aligned (Data-Oriented Design):** Implemented in **Odin** for host CPU RAM. Each neuron occupies exactly **256 Bytes** (perfectly aligned to 4 $\times$ 64-byte cache lines), keeping active wavefronts entirely inside L2/L3 CPU cache.
* **Cognitive Dynamics:** Two-wave predictive settlement (Wave 1 feedforward sweep + Wave 2 recurrent top-down convergence + Wave 3 residual consolidation).
* **Tri-Phasic Offline Sleep:** Synaptic maintenance and homeostatic downscaling through three explicit phases: *Visualization* (replay) $\rightarrow$ *Consolidation* (Cognitive RAG & synaptic tagging) $\rightarrow$ *Cryogenesis* (standby freeze).


---

## Authors & Credits

* **Principal Architect & Lead Designer:** **Teufel**  
  *Core system architecture, biophysical framework, and mathematical design*
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
