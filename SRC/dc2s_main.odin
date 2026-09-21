package main

import "core:fmt"
import "core:math"
import "core:math/bits"
import "core:math/linalg"
import "core:mem"
import virtual "core:mem/virtual"
import "core:time"
import ecs "odecs" // Busca la carpeta "odecs" relativa a main.odin

CACHE_LINE_ALIGNMENT :: 64

// =============================================================================
// ESTRUCTURA DE LA NEURONA (192 Bytes Exactos) - INTACTA
// =============================================================================
Neuron :: struct #packed #align(CACHE_LINE_ALIGNMENT) {
	// --- 1. Soma & ALIF Dynamic State (7 Bytes) ---
	v_membrane:             i16,    // Voltaje de membrana (2B)
	v_threshold:            i16,    // Umbral adaptativo (2B)
	histeresis:             i16,    // Histéresis del canal ionizado (2B)
	refractario:            u8,     // Periodo refractario / Diodo de dirección (1B)

	// --- 2. Interneuronas Parasitarias (2 Bytes) ---
	gating_somatic:         i8,     // SST+ (Gating somático) (1B)
	gating_context:         i8,     // VIP+ (Gating de contexto) (1B)

	// --- 3. Información del Soma (20 Bytes) ---
	nmda_latch:             u8,     // Memoria de trabajo local (1B)
	t_last:                 u32,    // Timestamp de último disparo (4B)
	t_prev:                 u32,    // Timestamp de disparo previo (4B)
	stdp_pre:               u8,     // Traza STDP pre-sináptica (1B)
	stdp_post:              u8,     // Traza STDP post-sináptica (1B)
	stdp_triplet:           u8,     // Traza Triplet STDP (post lenta) (1B)
	eligibility_fast:       u8,     // Traza de elegibilidad rápida (1B)
	eligibility_slow:       u8,     // Traza de elegibilidad lenta (1B)
	calcium_trace:          u16,    // Traza de calcio intracelular [Ca2+] (2B)
	frequency_homeostasis:  u8,     // Homeostasis de frecuencia (1B)
	axon_delay_exc:         u8,     // Axon delay excitador (1B)
	axon_delay_inh:         u8,     // Axon delay inhibidor (1B)
	axon_delay_desinh:      u8,     // Axon delay desinhibidor (1B)

	// --- 4. Conexiones Sinápticas (84 Bytes — Nibbles / INT4) ---
	axons_exc:              [64]u8, // 128 Axones excitadores (128 pesos @ 4 bits) (64B)
	axons_inh:              [16]u8, // 32 Axones inhibidores (32 pesos @ 4 bits) (16B)
	axons_desinh:           [4]u8,  // 8 Axones desinhibidores (8 pesos @ 4 bits) (4B)

	// --- 5. Árbol Dendrítico (48 Bytes) ---
	dendrites_sec:          [16]u8, // 16 Dendritas secundarias (16B)
	dendrites_prim:         [8]u8,  // 8 Dendritas primarias (8B)
	gating_dendritic:       [24]u8, // 24 Gating dendrítico (24B)

	// --- 6. Dendritas MoDE (12 Bytes) ---
	dendrites_mode:         [4]u8,  // 4 Dendritas MoDE (4B)
	gating_mode:            [4]u8,  // 4 Gating MoDE (4B)
	routers_som:            [4]u8,  // 4 Enrutadores (SOM+) (4B)

	// --- 7. Información Dendritas MoDE (4 Bytes) ---
	stdp_pre_mode:          u8,     // 1 Traza STDP Pre MoDE (1B)
	stdp_post_mode:         u8,     // 1 Traza STDP Post MoDE (1B)
	stdp_post_slow_mode:    u8,     // 1 Traza STDP Post Lenta MoDE (1B)
	homeostasis_mode:       u8,     // 1 Homeostasis de expertos (1B)

	// --- 8. Plasticidad a Corto Plazo — STP Tsodyks-Markram (7 Bytes) ---
	stp_u:                  u16,    // Estado de utilización (u) (2B)
	stp_r:                  u16,    // Estado de recursos (R) (2B)
	stp_tau_fac:            u8,     // Decaimiento de facilitación (tau_fac) (1B)
	stp_tau_rec:            u8,     // Recuperación de depósito (tau_rec) (1B)
	stp_u0:                 u8,     // Sensibilidad basal (U0) (1B)

	// --- 9. Extras, Control & Metaplasticidad (8 Bytes) ---
	bitfield:               u16,    // 16 Flags de estado somático (2B)
	plasticity_fractional:  u16,    // Plasticidad fraccionaria (acumulador estocástico) (2B)
	bcm_threshold:          u16,    // Umbral metaplástico BCM (2B)
	prng_seed:              u16,    // Semilla PRNG local (Xorshift16 determinista) (2B)
}

// Comprobaciones estrictas en tiempo de compilación
#assert(size_of(Neuron) == 192, "Error: Neuron debe medir exactamente 192 bytes")
#assert(align_of(Neuron) == CACHE_LINE_ALIGNMENT, "Error: Neuron debe estar alineada a 64 bytes")

// =============================================================================
// GESTIÓN DE MEMORIA VIRTUAL & ID POR POSICIÓN DE MEMORIA
// =============================================================================
PAGE_SIZE :: 4 * mem.Kilobyte

// ID único basado en la dirección directa de memoria
Neuron_ID :: distinct uintptr

Neuron_Pool :: struct {
	base:            rawptr,
	reserved_bytes:  uint,
	committed_bytes: uint,
	count:           uint,
}

pool_init :: proc(pool: ^Neuron_Pool, max_neurons: uint) -> bool {
	pool.reserved_bytes = mem.align_forward_uint(max_neurons * size_of(Neuron), PAGE_SIZE)
	buffer, err := virtual.reserve(pool.reserved_bytes)
	if err != nil {
		fmt.eprintln("Fallo al reservar espacio de memoria virtual:", err)
		return false
	}
	pool.base = raw_data(buffer)
	pool.committed_bytes = 0
	pool.count = 0
	return true
}

pool_destroy :: proc(pool: ^Neuron_Pool) {
	if pool.base != nil {
		virtual.release(pool.base, pool.reserved_bytes)
		pool.base = nil
	}
}

// Reserva una neurona y devuelve su puntero y su ID por posición de memoria
pool_alloc_neuron :: proc(pool: ^Neuron_Pool) -> (^Neuron, Neuron_ID) {
	needed_bytes := (pool.count + 1) * size_of(Neuron)

	// Si superamos las páginas físicas actuales, confirmamos (commit) nuevas páginas
	if needed_bytes > pool.committed_bytes {
		bytes_to_commit := mem.align_forward_uint(needed_bytes - pool.committed_bytes, PAGE_SIZE)
		commit_addr := rawptr(uintptr(pool.base) + uintptr(pool.committed_bytes))
		err := virtual.commit(commit_addr, bytes_to_commit)
		if err != nil {
			fmt.eprintln("Error al hacer commit de páginas físicas:", err)
			return nil, 0
		}
		pool.committed_bytes += bytes_to_commit
	}

	ptr := cast(^Neuron)(uintptr(pool.base) + uintptr(pool.count * size_of(Neuron)))
	pool.count += 1

	// La posición física de memoria es el identificador único O(1)
	id := Neuron_ID(uintptr(ptr))
	return ptr, id
}

// Acceso instantáneo a la neurona usando su ID
get_neuron :: #force_inline proc(id: Neuron_ID) -> ^Neuron {
	return cast(^Neuron)uintptr(id)
}

// =============================================================================
// MAIN DE PRUEBA Y CONEXIÓN
// =============================================================================
main :: proc() {
	// 1. Inicializamos pool con capacidad virtual para 100,000 neuronas
	pool: Neuron_Pool
	if !pool_init(&pool, 100_000) {
		return
	}
	defer pool_destroy(&pool)

	// 2. Inicializamos ECS
	world := ecs.create_world()
	defer ecs.delete_world(world)

	// 3. Crear una Neurona asignando su memoria física bajo demanda
	n1, id1 := pool_alloc_neuron(&pool)
	n1.v_membrane = -70
	n1.v_threshold = -55
	n1.t_last = u32(time.duration_milliseconds(time.since(time.Time{}))) // Usando core:time

	// Modificar flags de bitfield con core:math/bits
	n1.bitfield = bits.bitfield_insert(n1.bitfield, u16(1), 0, 1) // Bit 0 activo

	// 4. Registrar en el ECS como Entidad asociada a su ID de memoria
	entity := ecs.add_entity(world, id1)

	// 5. Lectura y verificación O(1) mediante el ID de memoria
	recuperada := get_neuron(id1)
	fmt.printfln("Neurona alojada en ID (Memoria): 0x%X", uintptr(id1))
	fmt.printfln("Membrana: %d mV | Umbral: %d mV | Bitfield: 0x%04X", 
		recuperada.v_membrane, recuperada.v_threshold, recuperada.bitfield)
	fmt.printfln("Bytes físicos comiteados en RAM: %d KB", pool.committed_bytes / mem.Kilobyte)
}

// =============================================================================
// CONTENEDOR DE RED (Con Memoria Virtual Paginada)
// =============================================================================
PAGE_SIZE :: 4 * mem.Kilobyte

Network :: struct {
	neurons:         []Neuron,
	base_ptr:        uintptr,
	total_neurons:   int,
	active_indices:  [dynamic]int,
	current_tick:    u32,
	target_sparsity: f32,
}

// Cálculo de índice relativo mediante aritmética de punteros en memoria (O(1) puro)
neuron_index_from_ptr :: #force_inline proc(net: ^Network, n_ptr: ^Neuron) -> int {
	return int((uintptr(n_ptr) - net.base_ptr) / size_of(Neuron))
}

// Inicialización con Memoria Virtual (reserve + commit por páginas de SO)
init_network :: proc(neuron_count: int, sparsity: f32 = 0.0025) -> ^Network {
	net := new(Network)
	net.total_neurons   = neuron_count
	net.target_sparsity = sparsity
	net.current_tick    = 0

	initial_capacity := int(f32(neuron_count) * sparsity * 2)
	net.active_indices = make([dynamic]int, 0, initial_capacity)

	// Alineamos los bytes requeridos al tamaño de página del sistema (4 KB)
	total_bytes := mem.align_forward_uint(uint(neuron_count * size_of(Neuron)), PAGE_SIZE)

	// 1. Reserva del espacio virtual contiguo
	buf, r_err := virtual.reserve(total_bytes)
	if r_err != nil {
		fmt.panicf("Error al reservar memoria virtual para la red: %v", r_err)
	}

	// 2. Confirmación (commit) de páginas físicas de RAM
	c_err := virtual.commit(raw_data(buf), total_bytes)
	if c_err != nil {
		fmt.panicf("Error al comitear páginas físicas de memoria virtual: %v", c_err)
	}

	// La memoria virtual del SO siempre viene alineada a páginas (4096B),
	// lo cual garantiza automáticamente la alineación de 64 bytes (línea de caché).
	raw_mem := raw_data(buf)
	net.neurons  = mem.slice_ptr(cast(^Neuron)raw_mem, neuron_count)
	net.base_ptr = uintptr(raw_mem)

	// Inicialización basal (Valores originales intactos)
	for i in 0..<neuron_count {
		n := &net.neurons[i]

		n.v_membrane             = 0
		n.v_threshold            = 68   // 15 es ~22% de 68
		n.histeresis             = 0
		n.refractario            = 0

		n.gating_somatic         = 0
		n.gating_context         = 0
		n.nmda_latch             = 0
		n.t_last                 = 0
		n.t_prev                 = 0
		n.calcium_trace          = 0
		n.frequency_homeostasis  = 0
		n.axon_delay_exc         = 1
		n.axon_delay_inh         = 1
		n.axon_delay_desinh      = 1

		// Habilitar las compuertas dendríticas primarias para paso de señal
		for d in 0..<8 {
			n.gating_dendritic[d] = 1
		}

		// Pesos iniciales INT4: cargamos las primeras 8 conexiones espaciales con fuerza máxima (15)
		// Dos pesos por byte: 0xFF = dos conexiones con peso 15
		n.axons_exc[0] = 0xFF 
		n.axons_exc[1] = 0xFF 
		n.axons_exc[2] = 0xFF 
		n.axons_exc[3] = 0xFF 

		// STP Tsodyks-Markram
		n.stp_u                  = 13107 // U0 = 20%
		n.stp_r                  = 65535 // Depósito al 100%
		n.stp_tau_fac            = 15
		n.stp_tau_rec            = 40
		n.stp_u0                 = 51

		n.bitfield               = 0
		n.plasticity_fractional  = 0
		n.bcm_threshold          = 1000
		n.prng_seed              = u16((i * 31337 + 1) & 0xFFFF)
	}

	return net
}

// Liberación del espacio de memoria virtual
destroy_network :: proc(net: ^Network) {
	if net == nil do return
	delete(net.active_indices)

	total_bytes := mem.align_forward_uint(uint(net.total_neurons * size_of(Neuron)), PAGE_SIZE)
	virtual.release(rawptr(net.base_ptr), total_bytes)

	free(net)
}


// =============================================================================
// MAIN: PUNTO DE ENTRADA Y BENCHMARK REAL
// =============================================================================
main :: proc() {
	fmt.println("==================================================")
	fmt.println("       INICIALIZANDO MOTOR DC2S — NoTA           ")
	fmt.println("==================================================")

	NUM_NEURONS :: 250_000
	fmt.printf("[*] Struct Neuron: %d Bytes (Exacto)\n", size_of(Neuron))
	fmt.printf("[*] Instanciando red de %d neuronas en memoria...\n", NUM_NEURONS)

	start_mem := time.now()
	net := init_network(NUM_NEURONS)
	defer destroy_network(net)

	mem_mb := f32(net.total_neurons * size_of(Neuron)) / (1024.0 * 1024.0)
	fmt.printf("[+] Red instanciada en %.2f ms\n", time.duration_milliseconds(time.since(start_mem)))
	fmt.printf("[+] Memoria física: %.2f MB contiguos en RAM\n", mem_mb)

	// 1. Construir la topología 3D de Iris (50 x 50 x 100)
	build_iris_3d_grid(net)

	// 2. Disparar el Rayo en el centro de la cara de entrada (X=25, Y=25, Z=0)
	fmt.println("\n--- DISPARANDO TRUENO EXPERIMENTAL ---")
	inject_input_pulse(net, 25, 25, radius = 2)

	// 3. Ejecutar 40 ticks a través de loop.odin y medir la propagación
	TOTAL_TICKS :: 40
	fmt.printf("\n[*] Simulando %d Ticks a través de loop.odin (Bi-Wave)...\n", TOTAL_TICKS)
	fmt.println("----------------------------------------------------------------------")
	fmt.println(" Tick | Activas | Esparsidad | Profundidad Máx (Z) | Estado de Onda  ")
	fmt.println("----------------------------------------------------------------------")

	start_sim := time.now()
	max_z_reached := 0

	for t in 1..=TOTAL_TICKS {
		step_network(net)

		active_count := len(net.active_indices)
		sparsity_pct := (f32(active_count) / f32(net.total_neurons)) * 100.0

		// Encontrar la profundidad máxima en Z alcanzada por la onda en este tick
		current_max_z := 0
		for idx in net.active_indices {
			_, _, z := index_to_coord(idx)
			if z > current_max_z do current_max_z = z
		}
		if current_max_z > max_z_reached do max_z_reached = current_max_z

		// Diagnóstico del estado del rayo
		status := "Propagando..."
		if current_max_z == GRID_DIM_Z - 1 {
			status = "¡IMPACTO EN TIERRA (Z=99)!"
		} else if active_count == 0 {
			status = "Onda Disipada (Fin)"
		}

		fmt.printf(" %4d | %7d | %9.3f%% |       Z = %3d       | %s\n", 
			t, active_count, sparsity_pct, max_z_reached, status)

		// Si la energía se disipó por completo, terminamos la simulación
		if active_count == 0 do break
	}

	sim_duration := time.since(start_sim)
	fmt.println("----------------------------------------------------------------------")
	fmt.printf("[✓] Simulación completada en: %.2f ms de tiempo real de CPU\n", time.duration_milliseconds(sim_duration))
	fmt.printf("[+] Profundidad máxima alcanzada: Capa Z = %d / %d\n", max_z_reached, GRID_DIM_Z - 1)
	
	if max_z_reached >= GRID_DIM_Z - 1 {
		fmt.println("La onda cruzó el bloque 3D de extremo a extremo!")
	} else {
		fmt.println("[!] La onda se mitigó en el interior.")
	}

	fmt.println("==================================================")
}
