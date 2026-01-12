import Foundation
import AVFoundation
import CommonCrypto

struct ACRCloudService {
    static func recognizeMusic(fromAudioAt url: URL) async throws -> MusicMetadata? {
        // Load credentials from Secrets.plist
        guard let secretsPath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let secretsDict = NSDictionary(contentsOfFile: secretsPath),
              let host = secretsDict["host"] as? String,
              let accessKey = secretsDict["accessKey"] as? String,
              let accessSecret = secretsDict["accessSecret"] as? String,
              !host.isEmpty, !accessKey.isEmpty, !accessSecret.isEmpty else {
            print("⚠️ ACRCloud credentials not found in Secrets.plist - skipping music recognition")
            return nil
        }
        
        print("🎵 ACRCloudService: Starting music recognition")
        
        // Extract a short sample from the audio (first 10 seconds max, ACRCloud recommends 5-10 seconds)
        // ACRCloud requires WAV/PCM format for reliable fingerprinting
        // This is more efficient and still provides good recognition accuracy
        guard let audioSample = try? await extractAudioSampleAsWAV(from: url, maxDuration: 10.0) else {
            print("❌ ACRCloudService: Failed to extract audio sample")
            return nil
        }
        
        // Prepare the request
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let httpMethod = "POST"
        let httpURI = "/v1/identify"
        let dataType = "audio"
        let signatureVersion = "1"
        
        // Create string to sign for HMAC
        let stringToSign = [
            httpMethod,
            httpURI,
            accessKey,
            dataType,
            signatureVersion,
            timestamp
        ].joined(separator: "\n")
        
        // Generate HMAC-SHA1 signature
        guard let signature = hmacSHA1(string: stringToSign, key: accessSecret) else {
            print("❌ ACRCloudService: Failed to generate signature")
            return nil
        }
        
        // Build the request URL
        guard let requestURL = URL(string: "\(host)\(httpURI)") else {
            print("❌ ACRCloudService: Invalid host URL: \(host)")
            return nil
        }
        
        // Create multipart form data
        // ACRCloud recommends sending raw binary file instead of base64 for better performance
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let boundaryString = boundary
        
        // Add form fields
        let textFields: [(String, String)] = [
            ("access_key", accessKey),
            ("sample_bytes", String(audioSample.count)),
            ("data_type", dataType),
            ("signature_version", signatureVersion),
            ("signature", signature),
            ("timestamp", timestamp)
        ]
        
        // Add text fields first
        for (key, value) in textFields {
            body.append("--\(boundaryString)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add sample field as binary file (ACRCloud REST API prefers raw binary over base64)
        body.append("--\(boundaryString)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"sample\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioSample) // Send raw binary WAV data
        body.append("\r\n".data(using: .utf8)!)
        
        // Close multipart form
        body.append("--\(boundaryString)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        
        print("🎵 ACRCloudService: Sending request to \(host)\(httpURI)")
        print("🎵 ACRCloudService: Audio sample size: \(audioSample.count) bytes (\(audioSample.count / 1024) KB)")
        
        // Create URLSession with timeout configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 3.0 // 3 second timeout - quick response
        sessionConfig.timeoutIntervalForResource = 3.0 // 3 second timeout - quick response
        let session = URLSession(configuration: sessionConfig)
        
        // Send the request with timeout
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ ACRCloudService: Invalid HTTP response")
                return nil
            }
            
            print("🎵 ACRCloudService: Response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ ACRCloudService: API error (\(httpResponse.statusCode)): \(errorString)")
                }
                return nil
            }
            
            // Parse the JSON response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ ACRCloudService: Failed to parse JSON response")
                return nil
            }
            
            print("🎵 ACRCloudService: Response: \(json)")
            
            // Check if music was recognized
            guard let status = json["status"] as? [String: Any],
                  let code = status["code"] as? Int,
                  code == 0 else {
                print("🎵 ACRCloudService: No music recognized (status code: \(json["status"] as? [String: Any]? ?? ["code": "unknown"]))")
                return nil
            }
            
            // Extract metadata - ACRCloud returns metadata as a dictionary with "music" key containing an array
            guard let metadata = json["metadata"] as? [String: Any] else {
                print("❌ ACRCloudService: No metadata dictionary in response")
                print("🎵 ACRCloudService: Response keys: \(json.keys)")
                return nil
            }
            
            guard let music = metadata["music"] as? [[String: Any]] else {
                print("❌ ACRCloudService: No music array in metadata")
                print("🎵 ACRCloudService: Metadata keys: \(metadata.keys)")
                if let musicValue = metadata["music"] {
                    print("🎵 ACRCloudService: Music value type: \(type(of: musicValue))")
                }
                return nil
            }
            
            guard let firstTrack = music.first else {
                print("❌ ACRCloudService: Music array is empty")
                return nil
            }
            
            print("✅ ACRCloudService: Successfully extracted music metadata")
            
            // Extract track information
            let title = firstTrack["title"] as? String ?? "Unknown"
            
            // Extract artists - can be array of dictionaries
            var artist = "Unknown Artist"
            if let artists = firstTrack["artists"] as? [[String: Any]], let firstArtist = artists.first {
                artist = firstArtist["name"] as? String ?? "Unknown Artist"
            } else if let artistName = firstTrack["artist"] as? String {
                artist = artistName
            }
            
            // Extract album information
            let album = firstTrack["album"] as? [String: Any]
            let albumName = album?["name"] as? String
            
            // Extract label
            let label = firstTrack["label"] as? String
            
            print("🎵 ACRCloudService: Recognized: '\(title)' by \(artist)")
            if let albumName = albumName {
                print("🎵 ACRCloudService: Album: \(albumName)")
            }
            
            let source = [albumName, label].compactMap { $0 }.joined(separator: " • ")
            
            return MusicMetadata(
                title: title,
                artist: artist,
                source: source.isEmpty ? "ACRCloud" : source
            )
            
        } catch {
            // Provide more specific error messages
            let errorMessage: String
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    errorMessage = "Unable to identify music"
                    print("❌ ACRCloudService: Request timed out after 3 seconds")
                case .notConnectedToInternet:
                    errorMessage = "No internet connection. Please check your network settings."
                    print("❌ ACRCloudService: No internet connection")
                case .networkConnectionLost:
                    errorMessage = "Network connection lost. Please try again."
                    print("❌ ACRCloudService: Network connection lost")
                default:
                    errorMessage = "Network error: \(urlError.localizedDescription)"
                    print("❌ ACRCloudService: Request failed with URLError: \(urlError.localizedDescription)")
                }
            } else {
                errorMessage = "Recognition failed: \(error.localizedDescription)"
                print("❌ ACRCloudService: Request failed: \(error.localizedDescription)")
            }
            throw NSError(domain: "ACRCloudService", code: -100, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
    
    // Extract a short audio sample as WAV format (PCM) - ACRCloud requires this for fingerprinting
    // ACRCloud recommends 5-10 seconds for best recognition accuracy
    // Error code 2004 "Can't generate fingerprint" occurs when audio format is not suitable
    private static func extractAudioSampleAsWAV(from url: URL, maxDuration: Double) async throws -> Data {
        let asset = AVAsset(url: url)
        
        // Get actual duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Determine sample duration (min of maxDuration or actual duration, but at least 1 second, max 10 seconds)
        let sampleDuration = min(maxDuration, max(1.0, min(durationSeconds, 10.0)))
        let sampleTimeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: sampleDuration, preferredTimescale: 600))
        
        print("🎵 ACRCloudService: Extracting \(sampleDuration)s sample as WAV from \(durationSeconds)s audio")
        
        // Get audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw NSError(domain: "ACRCloudService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
        }
        
        // Create AVAssetReader to read raw PCM audio
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw NSError(domain: "ACRCloudService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create asset reader: \(error.localizedDescription)"])
        }
        
        // Configure reader output for PCM audio (ACRCloud-compatible format)
        // ACRCloud prefers: 44.1kHz (CD quality) for best music recognition, 16-bit PCM, stereo
        // Stereo provides better recognition accuracy for music
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44100, // 44.1kHz (CD quality) - ACRCloud recommends this for music
            AVNumberOfChannelsKey: 2 // Stereo (better for music recognition)
        ]
        
        // Create a composition to trim the audio to the desired time range
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "ACRCloudService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
        }
        
        // Insert the audio track segment for the time range
        // Get the actual available time range from the track
        let sourceTimeRange = try await audioTrack.load(.timeRange)
        let availableDuration = CMTimeGetSeconds(sourceTimeRange.duration)
        let availableStart = CMTimeGetSeconds(sourceTimeRange.start)
        
        print("🎵 ACRCloudService: Source audio range: start=\(availableStart)s, duration=\(availableDuration)s")
        print("🎵 ACRCloudService: Requested sample: start=\(CMTimeGetSeconds(sampleTimeRange.start))s, duration=\(CMTimeGetSeconds(sampleTimeRange.duration))s")
        
        // Calculate intersection of available range and requested range manually
        // The insertTimeRange parameter is relative to the source track's timeline
        // For audio files, sourceTimeRange typically starts at .zero, so we can use sampleTimeRange directly
        // But we need to ensure it doesn't exceed the available range
        
        let requestedStartSeconds = CMTimeGetSeconds(sampleTimeRange.start)
        let requestedDurationSeconds = CMTimeGetSeconds(sampleTimeRange.duration)
        let requestedEndSeconds = requestedStartSeconds + requestedDurationSeconds
        let availableEndSeconds = availableStart + availableDuration
        
        // Calculate intersection: latest start and earliest end
        let intersectionStartSeconds = max(availableStart, requestedStartSeconds)
        let intersectionEndSeconds = min(availableEndSeconds, requestedEndSeconds)
        let intersectionDurationSeconds = max(0, intersectionEndSeconds - intersectionStartSeconds)
        
        guard intersectionDurationSeconds > 0.5 else {
            print("❌ ACRCloudService: Intersection too short (\(intersectionDurationSeconds)s), minimum is 0.5s")
            throw NSError(domain: "ACRCloudService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Audio sample too short: \(intersectionDurationSeconds)s"])
        }
        
        // Create the intersection time range relative to the source track
        // insertTimeRange.start is relative to sourceTimeRange.start, not absolute
        let relativeStart = intersectionStartSeconds - availableStart
        let insertStart = CMTime(seconds: relativeStart, preferredTimescale: 600)
        let insertDuration = CMTime(seconds: intersectionDurationSeconds, preferredTimescale: 600)
        let insertTimeRange = CMTimeRange(start: insertStart, duration: insertDuration)
        
        print("🎵 ACRCloudService: Inserting audio range (relative to source): start=\(relativeStart)s, duration=\(intersectionDurationSeconds)s")
        
        do {
            try compositionTrack.insertTimeRange(insertTimeRange, of: audioTrack, at: .zero)
            print("✅ ACRCloudService: Successfully inserted audio range into composition")
        } catch {
            print("❌ ACRCloudService: Failed to insert time range: \(error.localizedDescription)")
            throw NSError(domain: "ACRCloudService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to insert time range: \(error.localizedDescription)"])
        }
        
        // Create reader for the composition (which is already trimmed)
        let compositionAsset = composition as AVAsset
        let compositionReader: AVAssetReader
        do {
            compositionReader = try AVAssetReader(asset: compositionAsset)
        } catch {
            throw NSError(domain: "ACRCloudService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition reader: \(error.localizedDescription)"])
        }
        
        let readerOutput = AVAssetReaderTrackOutput(track: compositionTrack, outputSettings: outputSettings)
        compositionReader.add(readerOutput)
        
        // Start reading
        guard compositionReader.startReading() else {
            let error = compositionReader.error ?? NSError(domain: "ACRCloudService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to start reading"])
            throw error
        }
        
        // Read all sample buffers and collect PCM data
        var pcmData = Data()
        var sampleBufferCount = 0
        let expectedPCMBytes = Int(CMTimeGetSeconds(insertTimeRange.duration) * 44100 * 2 * 2) // 44.1kHz * stereo * 2 bytes per sample
        
        print("🎵 ACRCloudService: Reading PCM audio, expected ~\(expectedPCMBytes) bytes for \(CMTimeGetSeconds(insertTimeRange.duration))s audio")
        
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            sampleBufferCount += 1
            
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                print("⚠️ ACRCloudService: Sample buffer \(sampleBufferCount) has no data buffer, skipping")
                continue
            }
            
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>? = nil
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            guard status == noErr, let pointer = dataPointer, length > 0 else {
                print("⚠️ ACRCloudService: Sample buffer \(sampleBufferCount) failed to get data pointer, status: \(status), length: \(length)")
                continue
            }
            
            // Copy the data from the CoreMedia buffer (memory is managed by CMSampleBuffer)
            // We must copy since the pointer becomes invalid after the sample buffer is released
            // Create a new Data buffer by copying the bytes
            let buffer = Data(bytes: pointer, count: length)
            pcmData.append(buffer)
        }
        
        let finalStatus = compositionReader.status
        print("🎵 ACRCloudService: Read \(sampleBufferCount) sample buffers, collected \(pcmData.count) bytes PCM, reader status: \(finalStatus.rawValue)")
        
        guard !pcmData.isEmpty else {
            let errorMsg = compositionReader.error?.localizedDescription ?? "No audio data read"
            print("❌ ACRCloudService: Failed to read audio data: \(errorMsg), status: \(finalStatus.rawValue)")
            throw NSError(domain: "ACRCloudService", code: -6, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio data: \(errorMsg)"])
        }
        
        // Validate PCM data size (should be roughly what we expect)
        let expectedMinBytes = Int(CMTimeGetSeconds(insertTimeRange.duration) * 44100 * 2 * 2 * 0.8) // 80% of expected minimum (stereo)
        if pcmData.count < expectedMinBytes {
            print("⚠️ ACRCloudService: PCM data size (\(pcmData.count) bytes) is smaller than expected minimum (\(expectedMinBytes) bytes)")
        }
        
        // Convert PCM data to WAV format (ACRCloud requires WAV headers)
        let wavData = createWAVFile(pcmData: pcmData, sampleRate: 44100, channels: 2, bitsPerSample: 16)
        
        // Validate WAV file size (should be at least header size + some PCM data)
        guard wavData.count > 44 else {
            print("❌ ACRCloudService: WAV file too small (\(wavData.count) bytes), minimum is 44 bytes (header only)")
            throw NSError(domain: "ACRCloudService", code: -7, userInfo: [NSLocalizedDescriptionKey: "WAV file too small"])
        }
        
        print("🎵 ACRCloudService: Successfully extracted \(pcmData.count) bytes PCM, created \(wavData.count) bytes (\(wavData.count / 1024) KB) WAV file")
        
        return wavData
    }
    
    // Create WAV file from PCM data (ACRCloud requires WAV format with proper headers)
    private static func createWAVFile(pcmData: Data, sampleRate: Int32, channels: Int16, bitsPerSample: Int16) -> Data {
        var wavData = Data()
        
        // Helper function to append little-endian integers
        func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
            var littleEndianValue = value.littleEndian
            withUnsafeBytes(of: &littleEndianValue) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        // WAV header
        // RIFF chunk descriptor
        wavData.append("RIFF".data(using: .ascii)!)
        let dataSize = UInt32(36 + pcmData.count) // File size - 8
        appendLittleEndian(dataSize, to: &wavData)
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt sub-chunk
        wavData.append("fmt ".data(using: .ascii)!)
        let fmtChunkSize: UInt32 = 16 // PCM format chunk size
        appendLittleEndian(fmtChunkSize, to: &wavData)
        let audioFormat: UInt16 = 1 // PCM
        appendLittleEndian(audioFormat, to: &wavData)
        appendLittleEndian(channels, to: &wavData)
        appendLittleEndian(sampleRate, to: &wavData)
        let byteRate = UInt32(sampleRate * Int32(channels) * Int32(bitsPerSample) / 8)
        appendLittleEndian(byteRate, to: &wavData)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        appendLittleEndian(blockAlign, to: &wavData)
        appendLittleEndian(bitsPerSample, to: &wavData)
        
        // data sub-chunk
        wavData.append("data".data(using: .ascii)!)
        let dataChunkSize = UInt32(pcmData.count)
        appendLittleEndian(dataChunkSize, to: &wavData)
        wavData.append(pcmData)
        
        return wavData
    }
    
    // Generate HMAC-SHA1 signature (ACRCloud requires SHA1 specifically)
    private static func hmacSHA1(string: String, key: String) -> String? {
        guard let messageData = string.data(using: .utf8),
              let keyData = key.data(using: .utf8) else {
        return nil
        }
        
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        
        keyData.withUnsafeBytes { keyBytes in
            messageData.withUnsafeBytes { messageBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                       keyBytes.baseAddress,
                       keyBytes.count,
                       messageBytes.baseAddress,
                       messageBytes.count,
                       &digest)
            }
        }
        
        let hmacData = Data(digest)
        return hmacData.base64EncodedString()
    }
}
