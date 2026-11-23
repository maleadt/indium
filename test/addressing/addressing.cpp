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

		keepPollingDevice = false;
		device->wakeupEventLoop();
		devicePollingThread.join();
	}

	Indium::finit();

	std::cout << (ok ? "All results as expected" : "Some results were wrong") << std::endl;

	return ok ? 0 : 1;
}
