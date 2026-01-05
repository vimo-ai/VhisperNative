//
//  NetworkConfig.swift
//  VhisperNative
//
//  Shared network configuration to avoid system proxy issues
//

import Foundation

/// Shared network configuration for all HTTP/WebSocket requests
enum NetworkConfig {
    /// Cached URLSession configuration that ignores system proxy
    /// This prevents errors when system proxy is configured but not running
    static let sessionConfiguration: URLSessionConfiguration = {
        let config = URLSessionConfiguration.default

        // Disable system proxy to avoid connection failures
        // when proxy is configured but not running
        config.connectionProxyDictionary = [:]

        // Reasonable timeouts
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        // Enable HTTP/2 for multiplexing
        config.httpMaximumConnectionsPerHost = 6

        // Allow cellular
        config.allowsCellularAccess = true

        return config
    }()

    /// Shared URLSession instance
    static let shared: URLSession = {
        URLSession(configuration: sessionConfiguration)
    }()

    /// Create a WebSocket task with proxy-free configuration
    static func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
        shared.webSocketTask(with: request)
    }

    /// Create a WebSocket task for a URL
    static func webSocketTask(with url: URL) -> URLSessionWebSocketTask {
        shared.webSocketTask(with: url)
    }
}
