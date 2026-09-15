package main

import "core:fmt"
import "core:mem"

// =============================================================================
// CORE STEP PIPELINE (Wave 1 -> Wave 2 -> ALIF Update)
// =============================================================================

step_network :: proc(net: ^Network) {
	net.current_tick += 1

	// In a complete step:
	// 1. VIP+ receives top-down bias, disinhibits SST+, configuring MoDE (Wave 2 preparation)
	// 2. Headless pairs compute coincidence detection from incoming spikes (Wave 1)
	// 3. Primary trees integrate bypasses and converge onto ALIF soma
	// 4. Somatic threshold evaluation & T-STDP eligibility update
}

