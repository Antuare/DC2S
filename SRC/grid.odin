package main

import "core:fmt"

// =========================================================================
// DIMENSIONES DEL ESPACIO 3D (IRIS) — 50 x 50 x 100 = 250.000 Neuronas
// =========================================================================
GRID_DIM_X :: 50
GRID_DIM_Y :: 50
GRID_DIM_Z :: 100

// Flags para el bitfield de la neurona (para que reconozca su entorno)
FLAG_INPUT_NODE  :: u16(1 << 0) // Neurona en la cara de entrada (Z = 0)
FLAG_OUTPUT_NODE :: u16(1 << 1) // Neurona en la cara de salida (Z = 99)
FLAG_WALL_NODE   :: u16(1 << 2) // Neurona pegada a una pared lateral concreta

// Offset diagonal de las 8 conexiones octantes en 3D: (±1, ±1, ±1)
OCTANT_OFFSETS := [8][3]int{
	{-1, -1, -1}, { 1, -1, -1}, {-1,  1, -1}, { 1,  1, -1},
	{-1, -1,  1}, { 1, -1,  1}, {-1,  1,  1}, { 1,  1,  1},
}

// -------------------------------------------------------------------------
// Conversión matemática entre Índice Lineal en RAM y Coordenadas (X, Y, Z)
// -------------------------------------------------------------------------

// Convierte (x, y, z) a índice lineal [0 .. 249_999]
coord_to_index :: #force_inline proc(x, y, z: int) -> int {
	return x + (y * GRID_DIM_X) + (z * GRID_DIM_X * GRID_DIM_Y)
}

// Convierte un índice lineal de vuelta a sus coordenadas espaciales
index_to_coord :: #force_inline proc(idx: int) -> (x: int, y: int, z: int) {
	z = idx / (GRID_DIM_X * GRID_DIM_Y)
	rem := idx % (GRID_DIM_X * GRID_DIM_Y)
	y = rem / GRID_DIM_X
	x = rem % GRID_DIM_X
	return
}

// Obtiene las coordenadas (X, Y, Z) directamente desde el puntero en RAM
ptr_to_coord :: #force_inline proc(net: ^Network, n_ptr: ^Neuron) -> (x: int, y: int, z: int) {
	idx := neuron_index_from_ptr(net, n_ptr)
	return index_to_coord(idx)
}

// -------------------------------------------------------------------------
// Cálculo de vecinos con Paredes Concretas (Sin toroide)
// -------------------------------------------------------------------------

// Retorna los índices de los 8 vecinos diagonales.
// Si choca contra una pared o el borde del mundo, retorna -1 (conexión bloqueada).
get_3d_neighbors :: proc(idx: int) -> [8]int {
	x, y, z := index_to_coord(idx)
	neighbors: [8]int

	for i in 0..<8 {
		nx := x + OCTANT_OFFSETS[i][0]
		ny := y + OCTANT_OFFSETS[i][1]
		nz := z + OCTANT_OFFSETS[i][2]

		// PAREDES CONCRETAS: Validación estricta de bordes (sin wrap-around)
		if nx >= 0 && nx < GRID_DIM_X &&
		   ny >= 0 && ny < GRID_DIM_Y &&
		   nz >= 0 && nz < GRID_DIM_Z {
			neighbors[i] = coord_to_index(nx, ny, nz)
		} else {
			neighbors[i] = -1 // Conexión bloqueada por pared física
		}
	}

	return neighbors
}

// -------------------------------------------------------------------------
// Construcción y marcado de la topología IRIS (3D)
// -------------------------------------------------------------------------

build_iris_3d_grid :: proc(net: ^Network) {
	fmt.println("[*] Construyendo topología IRIS (3D): 50 x 50 x 100...")

	input_count  := 0
	output_count := 0
	wall_count   := 0

	for i in 0..<net.total_neurons {
		n := &net.neurons[i]
		x, y, z := index_to_coord(i)

		// 1. Marcar Cara de Entrada (Z = 0)
		if z == 0 {
			n.bitfield |= FLAG_INPUT_NODE
			input_count += 1
		}

		// 2. Marcar Cara de Salida / Tierra (Z = 99)
		if z == GRID_DIM_Z - 1 {
			n.bitfield |= FLAG_OUTPUT_NODE
			output_count += 1
		}

		// 3. Marcar Paredes Concretas laterales (X o Y en los límites)
		if x == 0 || x == GRID_DIM_X - 1 || y == 0 || y == GRID_DIM_Y - 1 {
			n.bitfield |= FLAG_WALL_NODE
			wall_count += 1
		}
	}

	fmt.printf("[+] Topología 3D completada:\n")
	fmt.printf("    - Neuronas de Entrada (Z=0):   %d\n", input_count)
	fmt.printf("    - Neuronas de Salida  (Z=99):  %d\n", output_count)
	fmt.printf("    - Neuronas en Paredes Físicas: %d\n", wall_count)
}
