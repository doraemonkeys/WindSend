package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"os"
	"time"

	"github.com/sirupsen/logrus"
)

const certFile = "./tls/cert.pem"
const keyFile = "./tls/key.pem"

func InitTSLConfig() {
	// mkdir tls
	if !FileOrDirIsExist("./tls") {
		err := os.Mkdir("./tls", os.ModePerm)
		if err != nil {
			logrus.Panic(err)
		}
	}
	// check file
	if !FileOrDirIsExist(certFile) || !FileOrDirIsExist(keyFile) {
		rawCert, rawKey, err := GenerateKeyPair()
		if err != nil {
			logrus.Panic(err)
		}
		err = os.WriteFile(certFile, rawCert, 0644)
		if err != nil {
			logrus.Panic(err)
		}
		err = os.WriteFile(keyFile, rawKey, 0644)
		if err != nil {
			logrus.Panic(err)
		}
	}
}

func GenerateKeyPair() (rawCert, rawKey []byte, err error) {
	// Create private key and self-signed certificate
	// Adapted from https://golang.org/src/crypto/tls/generate_cert.go

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return
	}
	validFor := time.Hour * 24 * 365 * 10 // ten years
	notBefore := time.Now()
	notAfter := notBefore.Add(validFor)
	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, _ := rand.Int(rand.Reader, serialNumberLimit)
	template := x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			Organization: []string{"doraemon"},
		},
		NotBefore: notBefore,
		NotAfter:  notAfter,

		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		return
	}

	rawCert = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	rawKey = pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	return
}
