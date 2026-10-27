// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

#if canImport(Security) && canImport(CryptoKit)
import CryptoKit
import Foundation
import Security

/// A `URLSessionDelegate` that pins the TLS connection to one or more SubjectPublicKeyInfo
/// SHA-256 hashes (the same base64 values as HPKP / `openssl ... | openssl dgst -sha256 -binary | base64`).
///
/// The server trust is first evaluated normally (system or MDM-installed roots, hostname,
/// expiry); the connection is then accepted only if **some certificate in the chain** has a
/// public key whose SPKI hash is pinned. Pin your issuing CA or intermediate plus a backup key so
/// that leaf rotation does not break the app.
///
/// Supported key types: RSA 2048/3072/4096 and EC P-256/P-384/P-521.
///
/// ```swift
/// let pinning = PublicKeyPinningDelegate(
///     host: "consent.bank.example",
///     pinnedSPKISHA256Base64: ["r/mIkG3eEpVdm+u/ko/cwxzOMo1bk4TyHIlByibiA5E=",
///                              "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg="])
/// let session = ConsentSession(baseURL: url, sessionProvider: fetchToken,
///                              urlSession: ConsentSession.pinnedURLSession(delegate: pinning))
/// ```
///
/// Note: this file is compiled only on Apple platforms.
public final class PublicKeyPinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    public let host: String
    public let pins: Set<String>

    /// - Parameters:
    ///   - host: Only challenges for this host are pinned; any other host is rejected.
    ///   - pinnedSPKISHA256Base64: Base64 SHA-256 of DER SubjectPublicKeyInfo. Provide at least two.
    public init(host: String, pinnedSPKISHA256Base64: Set<String>) {
        self.host = host.lowercased()
        self.pins = pinnedSPKISHA256Base64
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.protectionSpace.host.lowercased() == host, evaluate(trust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// True when the chain is valid and at least one certificate's SPKI hash is pinned.
    public func evaluate(_ trust: SecTrust) -> Bool {
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else { return false }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return false }
        for certificate in chain {
            if let hash = Self.spkiSHA256Base64(certificate), pins.contains(hash) { return true }
        }
        return false
    }

    /// Base64 SHA-256 of the certificate's DER SubjectPublicKeyInfo.
    public static func spkiSHA256Base64(_ certificate: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(certificate),
              let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] as? String,
              let bits = attributes[kSecAttrKeySizeInBits] as? Int,
              let header = asn1Header(keyType: keyType, bits: bits),
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else { return nil }
        let digest = SHA256.hash(data: header + raw)
        return Data(digest).base64EncodedString()
    }

    /// DER prefixes that turn `SecKeyCopyExternalRepresentation` output (PKCS#1 for RSA, X9.63 for EC)
    /// into a SubjectPublicKeyInfo.
    static func asn1Header(keyType: String, bits: Int) -> Data? {
        let rsa = kSecAttrKeyTypeRSA as String
        let ec = kSecAttrKeyTypeECSECPrimeRandom as String
        let bytes: [UInt8]
        switch (keyType, bits) {
        case (rsa, 2048):
            bytes = [0x30, 0x82, 0x01, 0x22, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
                     0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0F, 0x00]
        case (rsa, 3072):
            bytes = [0x30, 0x82, 0x01, 0xA2, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
                     0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x8F, 0x00]
        case (rsa, 4096):
            bytes = [0x30, 0x82, 0x02, 0x22, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
                     0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0F, 0x00]
        case (ec, 256):
            bytes = [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A,
                     0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00]
        case (ec, 384):
            bytes = [0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x05, 0x2B,
                     0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00]
        case (ec, 521):
            bytes = [0x30, 0x81, 0x9B, 0x30, 0x10, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x05,
                     0x2B, 0x81, 0x04, 0x00, 0x23, 0x03, 0x81, 0x86, 0x00]
        default:
            return nil
        }
        return Data(bytes)
    }
}
#endif
