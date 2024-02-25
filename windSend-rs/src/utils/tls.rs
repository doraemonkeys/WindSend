use rcgen::{
    BasicConstraints, Certificate, CertificateParams, DistinguishedName, DnType, IsCa,
    KeyUsagePurpose, SanType,
};

use std::io::{Error, ErrorKind};
use time::{ext::NumericalDuration, OffsetDateTime};

pub fn gen_ca() -> Result<Certificate, Box<dyn std::error::Error>> {
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
        SanType::DnsName("localhost".to_string()),
        SanType::IpAddress(std::net::IpAddr::V4(std::net::Ipv4Addr::new(127, 0, 0, 1))),
        SanType::IpAddress(std::net::IpAddr::V6(std::net::Ipv6Addr::new(
            0, 0, 0, 0, 0, 0, 0, 1,
        ))),
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

    Ok(Certificate::from_params(params)?)

    // rcgen main branch
    // let key_pair = rcgen::KeyPair::generate()?;
    // Ok((
    //     Certificate::generate_self_signed(params, &key_pair)?,
    //     key_pair,
    // ))
}

pub fn generate_self_signed_cert_with_privkey(
) -> Result<(String, String), Box<dyn std::error::Error>> {
    // // rcgen main branch
    // let (cert, key_pair) = gen_ca()?;

    let cert = gen_ca()?;
    let cert_crt = cert.serialize_pem()?;

    let private_key = cert.serialize_private_key_pem();
    Ok((cert_crt, private_key))
}
