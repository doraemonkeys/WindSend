use rcgen::{
    BasicConstraints, Certificate, CertificateParams, DistinguishedName, DnType, IsCa, KeyPair,
    KeyUsagePurpose, SanType,
};

use std::{
    io::{Error, ErrorKind},
    str::FromStr,
};
use time::{ext::NumericalDuration, OffsetDateTime};

pub fn generate_signed_certificate(
    issuer: &Certificate,
    issuer_key: &KeyPair,
) -> Result<(Certificate, KeyPair), Box<dyn std::error::Error>> {
    let mut params = CertificateParams::default();
    let mut distinguished_name = DistinguishedName::new();
    distinguished_name.push(DnType::CommonName, crate::PROGRAM_NAME);
    distinguished_name.push(DnType::OrganizationName, "doraemon");
    distinguished_name.push(DnType::CountryName, "CN");
    distinguished_name.push(DnType::LocalityName, "CN");
    params.distinguished_name = distinguished_name;
    params.key_usages = vec![
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::CrlSign,
    ];
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    params.subject_alt_names = vec![
        SanType::DnsName(rcgen::Ia5String::from_str("localhost")?),
        SanType::IpAddress(std::net::IpAddr::V4(std::net::Ipv4Addr::new(127, 0, 0, 1))),
        SanType::IpAddress(std::net::IpAddr::V6(std::net::Ipv6Addr::new(
            0, 0, 0, 0, 0, 0, 0, 1,
        ))),
        SanType::DnsName(rcgen::Ia5String::from_str("fake.windsend.com")?),
        // SanType::IpAddress(std::net::IpAddr::V4(std::net::Ipv4Addr::new(
        //     192, 168, 1, 7,
        // ))),
    ];
    // 当前时间
    params.not_before = OffsetDateTime::now_utc();
    // 当前时间 + 3650 , 即有效期10年
    params.not_after = params
        .not_before
        .checked_add(3650.days())
        .ok_or(Error::new(
            ErrorKind::InvalidInput,
            format!("invalid time: {}", params.not_after),
        ))?;
    // params.alg = &rcgen::PKCS_ECDSA_P256_SHA256;

    let key_pair = rcgen::KeyPair::generate()?;
    Ok((params.signed_by(&key_pair, issuer, issuer_key)?, key_pair))
}

pub fn generate_self_signed_ca_certificate(
) -> Result<(Certificate, KeyPair), Box<dyn std::error::Error>> {
    let mut params = CertificateParams::default();
    let mut distinguished_name = DistinguishedName::new();
    distinguished_name.push(DnType::CommonName, "Doraemon CA");
    distinguished_name.push(DnType::OrganizationName, "doraemon");
    distinguished_name.push(DnType::CountryName, "CN");
    distinguished_name.push(DnType::LocalityName, "CN");
    params.distinguished_name = distinguished_name;
    params.key_usages = vec![
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::CrlSign,
    ];
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    params.subject_alt_names = vec![
        SanType::DnsName(rcgen::Ia5String::from_str("localhost")?),
        SanType::IpAddress(std::net::IpAddr::V4(std::net::Ipv4Addr::new(127, 0, 0, 1))),
        SanType::IpAddress(std::net::IpAddr::V6(std::net::Ipv6Addr::new(
            0, 0, 0, 0, 0, 0, 0, 1,
        ))),
    ];
    params.not_before = OffsetDateTime::now_utc();
    params.not_after = params
        .not_before
        .checked_add(3650.days())
        .ok_or(Error::new(
            ErrorKind::InvalidInput,
            format!("invalid time: {}", params.not_after),
        ))?;

    let key_pair = rcgen::KeyPair::generate()?;
    let cert = params.self_signed(&key_pair)?;
    Ok((cert, key_pair))
}

pub fn generate_ca_and_signed_certificate_pair(
) -> Result<([String; 2], [String; 2]), Box<dyn std::error::Error>> {
    let (ca_cert, ca_key) = generate_self_signed_ca_certificate()?;
    let (cert, key_pair) = generate_signed_certificate(&ca_cert, &ca_key)?;
    Ok((
        [cert.pem(), key_pair.serialize_pem()],
        [ca_cert.pem(), ca_key.serialize_pem()],
    ))
}
