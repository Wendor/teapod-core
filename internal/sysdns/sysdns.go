// Package sysdns — DNS-транспорт sing-box `local` через системный резолвер.
// Стандартный `local` читает /etc/resolv.conf, которого на Android нет; Go на
// Android резолвит через bionic (cgo), а UID приложения исключён из VPN.
package sysdns

import (
	"context"
	"errors"
	"net"
	"strings"

	"github.com/miekg/dns"
	"github.com/sagernet/sing-box/adapter"
	C "github.com/sagernet/sing-box/constant"
	boxdns "github.com/sagernet/sing-box/dns"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
)

// Register заменяет транспорт `local` в реестре DNS.
func Register(registry *boxdns.TransportRegistry) {
	boxdns.RegisterTransport[option.LocalDNSServerOptions](registry, C.DNSTypeLocal,
		func(_ context.Context, _ log.ContextLogger, tag string, options option.LocalDNSServerOptions) (adapter.DNSTransport, error) {
			return New(tag, options), nil
		})
}

var _ adapter.DNSTransport = (*Transport)(nil)

type Transport struct {
	boxdns.TransportAdapter
	resolver *net.Resolver
}

func New(tag string, options option.LocalDNSServerOptions) *Transport {
	return &Transport{
		TransportAdapter: boxdns.NewTransportAdapterWithLocalOptions(C.DNSTypeLocal, tag, options),
		resolver:         net.DefaultResolver,
	}
}

func (t *Transport) Start(adapter.StartStage, *adapter.Scope) error { return nil }

func (t *Transport) Close() error { return nil }

func (t *Transport) Reset() {}

// Exchange отвечает только на A/AAAA: системный резолвер других типов не отдаёт.
func (t *Transport) Exchange(ctx context.Context, message *dns.Msg) (*dns.Msg, error) {
	if len(message.Question) == 0 {
		return nil, errors.New("sysdns: empty question")
	}
	question := message.Question[0]
	var network string
	switch question.Qtype {
	case dns.TypeA:
		network = "ip4"
	case dns.TypeAAAA:
		network = "ip6"
	default:
		return nil, errors.New("sysdns: only A/AAAA queries are supported")
	}
	addresses, err := t.resolver.LookupNetIP(ctx, network, strings.TrimSuffix(question.Name, "."))
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) && dnsErr.IsNotFound {
		return boxdns.FixedResponse(message.Id, question, nil, C.DefaultDNSTTL), nil
	}
	if err != nil {
		return nil, err
	}
	return boxdns.FixedResponse(message.Id, question, addresses, C.DefaultDNSTTL), nil
}

func (t *Transport) ExchangeAsync(ctx context.Context, message *dns.Msg, callback func(response *dns.Msg, err error)) {
	go func() { callback(t.Exchange(ctx, message)) }()
}
