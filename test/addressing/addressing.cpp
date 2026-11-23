// Copyright (C) 2026 Darling Developers
//
// Runs the kernels in addressing.metallib on the system default device. Each kernel addresses memory
// through a pointer shape that AIR producers emit (see shadersrc/addressing.ll) and writes one int per
// thread; the host computes the expected value of each.

#include "addressing.h"

#include <indium/indium.hpp>

#include <cstdint>
#include <cstring>
#include <functional>
#include <iostream>
#include <thread>
#include <vector>

#ifndef ENABLE_VALIDATION
	#define ENABLE_VALIDATION (!!getenv("INDIUM_TEST_VALIDATION"))
#endif

static constexpr size_t threadCount = 32;

// Runs `name` on one threadgroup of threadCount threads with the output in buffer 0 and `input` in buffer 1, and
// compares out[i] with want(i).
static bool check(Indium::Device* device, std::shared_ptr<Indium::Library> library, const char* name, std::shared_ptr<Indium::Buffer> input,
	const std::vector<std::shared_ptr<Indium::Buffer>>& indirect, const std::function<int32_t(int32_t)>& want)
{
	std::vector<int32_t> poison(threadCount);
	std::memset(poison.data(), 0xA5, poison.size() * sizeof(int32_t));

	auto pipeline = device->newComputePipelineState(library->newFunction(name));
	auto queue = device->newCommandQueue();
	auto output = device->newBuffer(poison.data(), poison.size() * sizeof(int32_t), Indium::ResourceOptions::StorageModeShared);

	auto commandBuffer = queue->commandBuffer();
	auto encoder = commandBuffer->computeCommandEncoder();
	encoder->setComputePipelineState(pipeline);
	encoder->setBuffer(output, 0, 0);
	encoder->setBuffer(input, 0, 1);
	if (!indirect.empty()) {
		std::vector<std::shared_ptr<Indium::Resource>> resources(indirect.begin(), indirect.end());
		encoder->useResources(resources, Indium::ResourceUsage::Read);
	}
	encoder->dispatchThreads(Indium::Size { threadCount, 1, 1 }, Indium::Size { threadCount, 1, 1 });
	encoder->endEncoding();
	commandBuffer->commit();
	commandBuffer->waitUntilCompleted();

	auto got = static_cast<const int32_t*>(output->contents());
	size_t bad = 0;
	for (size_t i = 0; i < threadCount; ++i) {
		if (got[i] != want(i) && bad++ < 8) {
			std::cerr << name << ": thread " << i << ": got " << got[i] << ", expected " << want(i) << std::endl;
		}
	}
	std::cout << (bad ? "FAIL " : "PASS ") << name << std::endl;
	return bad == 0;
}

template<typename T>
static std::shared_ptr<Indium::Buffer> buffer(Indium::Device* device, const std::vector<T>& contents) {
	return device->newBuffer(contents.data(), contents.size() * sizeof(T), Indium::ResourceOptions::StorageModeShared);
}

// The binary16 encoding of a small integer (exact, so no rounding is involved).
static uint16_t half(int32_t value) {
	if (value == 0) {
		return 0;
	}
	uint16_t sign = value < 0 ? 0x8000 : 0;
	uint32_t magnitude = value < 0 ? -value : value;
	int exponent = 31 - __builtin_clz(magnitude);
	uint32_t mantissa = (magnitude << (10 - exponent)) & 0x3ff;
	return sign | ((exponent + 15) << 10) | mantissa;
}

static std::vector<int32_t> ramp(size_t count) {
	std::vector<int32_t> values(count);
	for (size_t i = 0; i < count; ++i) {
		values[i] = 3 * static_cast<int32_t>(i) + 1;
	}
	return values;
}

int main(int argc, char** argv) {
	Indium::init(nullptr, 0, ENABLE_VALIDATION);

	bool ok = true;

	{
		auto device = Indium::createSystemDefaultDevice();

		bool keepPollingDevice = true;
		std::thread devicePollingThread([device, &keepPollingDevice]() {
			while (keepPollingDevice) {
				device->pollEvents(UINT64_MAX);
			}
		});

		auto library = device->newLibrary(addressing_metallib, addressing_metallib_len);
		auto values = ramp(2 * threadCount);
		auto in = buffer(device.get(), values);

		ok = check(device.get(), library, "undeclared_struct", buffer(device.get(), std::vector<int32_t> { 5, 1000 }), {},
			[](int32_t i) { return 1000 + i; }) && ok;

		std::vector<uint64_t> array { in->gpuAddress(), values.size() };
		ok = check(device.get(), library, "loaded_pointer", buffer(device.get(), array), { in },
			[&](int32_t i) { return 2 * values[i]; }) && ok;

		ok = check(device.get(), library, "pointer_select", in, {}, [&](int32_t i) { return values[i % 2 ? i : i + 32]; }) && ok;
		ok = check(device.get(), library, "pointer_phi", in, {}, [&](int32_t i) { return values[i] + values[i + 1] + values[i + 2] + values[i + 3]; }) && ok;
		ok = check(device.get(), library, "pointer_integer", in, {}, [&](int32_t i) { return values[i + 1]; }) && ok;

		ok = check(device.get(), library, "threadgroup_derived", in, {}, [&](int32_t i) { return values[i + 1]; }) && ok;
		ok = check(device.get(), library, "private_derived", in, {}, [&](int32_t i) { return values[i + (i & 3)] + values[i + (i & 3) + 1]; }) && ok;
		ok = check(device.get(), library, "threadgroup_bytes", in, {}, [&](int32_t i) { return values[31 - i]; }) && ok;
		ok = check(device.get(), library, "threadgroup_subword", in, {}, [&](int32_t i) { return values[31 - i] & 0xff; }) && ok;
		ok = check(device.get(), library, "threadgroup_phi", in, {},
			[&](int32_t i) {
				int32_t sum = 0;
				for (int32_t k = 0; k < 4 + (i & 3); ++k) {
					sum += values[i + k];
				}
				return i % 2 ? sum : -1;
			}) && ok;
		ok = check(device.get(), library, "threadgroup_atomic", in, {}, [&](int32_t i) { return int32_t(threadCount); }) && ok;

		ok = check(device.get(), library, "threadgroup_punning", in, {}, [&](int32_t i) { return 2 * values[(i + 1) & 31] + values[i]; }) && ok;
		ok = check(device.get(), library, "threadgroup_mixed_width", in, {},
			[&](int32_t i) { int k = i & 3; return values[k] + (31 - i) + values[3 - k] + (3 - k); }) && ok;
		ok = check(device.get(), library, "private_punning", in, {}, [&](int32_t i) {
			uint16_t a = half(values[i]), b = half(values[i + 1]);
			return i & 1 ? int32_t(b | uint32_t(a) << 16) : int32_t(a | uint32_t(b) << 16);
		}) && ok;
		ok = check(device.get(), library, "threadgroup_dead", in, {}, [&](int32_t i) { return values[i]; }) && ok;

		ok = check(device.get(), library, "private_merged", in, {},
			[&](int32_t i) { return i % 2 ? values[i + (i & 3)] + 1000 : values[i + (i & 3) + 8]; }) && ok;
		ok = check(device.get(), library, "threadgroup_merged", in, {}, [&](int32_t i) { return values[31 - i + (i % 2 ? 0 : 32)]; }) && ok;

		keepPollingDevice = false;
		device->wakeupEventLoop();
		devicePollingThread.join();
	}

	Indium::finit();

	std::cout << (ok ? "All results as expected" : "Some results were wrong") << std::endl;

	return ok ? 0 : 1;
}
