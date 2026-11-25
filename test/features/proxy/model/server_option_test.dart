import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/model/server_option.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  group('ServerOption.parse', () {
    test('parses Arco servers and skips balancers', () {
      final group = OutboundGroup(
        tag: 'select',
        selected: 'fr-tcp',
        items: [
          OutboundInfo(
            tag: 'nl-ws',
            tagDisplay: 'Netherlands (Arco) [ws]',
            urlTestDelay: 120,
          ),
          OutboundInfo(
            tag: 'fr-tcp',
            tagDisplay: 'France (Arco) [tcp]',
            urlTestDelay: 90,
          ),
          OutboundInfo(
            tag: 'pl-tcp',
            tagDisplay: 'Poland (Arco) [tcp]',
            urlTestDelay: 200,
          ),
          OutboundInfo(
            tag: 'lowest',
            tagDisplay: 'lowest',
            isGroup: true,
          ),
          OutboundInfo(
            tag: 'balance',
            tagDisplay: 'balance',
          ),
        ],
      );

      final options = ServerOption.parse(group);

      expect(options, hasLength(3));
      expect(
        options.map((o) => (o.country, o.protocol, o.transport, o.rawTag, o.delay)),
        containsAll([
          ('Netherlands', 'vless', 'ws', 'nl-ws', 120),
          ('France', 'vless', 'tcp', 'fr-tcp', 90),
          ('Poland', 'vless', 'tcp', 'pl-tcp', 200),
        ]),
      );

      final countries = ServerOption.countries(options).toList()..sort();
      expect(countries, ['France', 'Netherlands', 'Poland']);

      expect(ServerOption.protocolsFor(options, 'France'), ['vless']);
      expect(ServerOption.protocolsFor(options, 'Netherlands'), ['vless']);
      expect(ServerOption.transportsFor(options, 'France', 'vless'), ['tcp']);
      expect(ServerOption.transportsFor(options, 'Netherlands', 'vless'), ['ws']);

      final found = ServerOption.find(options, 'France', 'vless', 'tcp');
      expect(found?.rawTag, 'fr-tcp');
    });

    test('parses servers regardless of the username in parentheses', () {
      final group = OutboundGroup(
        tag: 'select',
        selected: 'nl-ws',
        items: [
          OutboundInfo(tag: 'nl-ws', tagDisplay: 'Netherlands (ivan123) [ws]', urlTestDelay: 110),
          OutboundInfo(tag: 'de-tcp', tagDisplay: 'United States (some.user_42) [tcp]', urlTestDelay: 80),
        ],
      );

      final options = ServerOption.parse(group);

      expect(options, hasLength(2));
      expect(
        options.map((o) => (o.country, o.protocol, o.transport, o.rawTag)),
        containsAll([
          ('Netherlands', 'vless', 'ws', 'nl-ws'),
          ('United States', 'vless', 'tcp', 'de-tcp'),
        ]),
      );
    });

    test('fastest picks lowest delay across country and transport', () {
      final options = [
        ServerOption(country: 'Netherlands', protocol: 'vless', transport: 'ws', rawTag: 'nl-ws', delay: 120),
        ServerOption(country: 'France', protocol: 'vless', transport: 'tcp', rawTag: 'fr-tcp', delay: 90),
        ServerOption(country: 'Poland', protocol: 'vless', transport: 'tcp', rawTag: 'pl-tcp', delay: 200),
      ];

      expect(ServerOption.fastest(options)?.rawTag, 'fr-tcp');
      expect(ServerOption.fastest([]), isNull);
      expect(
        ServerOption.fastest([
          ServerOption(country: 'France', protocol: 'vless', transport: 'tcp', rawTag: 'fr-tcp', delay: 0),
        ]),
        isNull,
      );
    });
  });

  group('remembered selection', () {
    ServerOption o(String country, String protocol, String transport) => ServerOption(
          country: country,
          protocol: protocol,
          transport: transport,
          rawTag: '$country [$transport]',
          delay: 100,
        );

    test('countryCode reads the flag or the name, English or Russian', () {
      for (final name in ['🇺🇸 USA dev', 'USA', 'United States', 'США', 'usa-dev']) {
        expect(ServerOption.countryCode(name), 'US', reason: name);
      }
      expect(ServerOption.countryCode('🇩🇪Германия [Билайн]'), 'DE');
      expect(ServerOption.countryCode('Germany #2'), 'DE');
      expect(ServerOption.countryCode('South Korea'), 'KR');
      expect(ServerOption.countryCode('🔁 Запасной'), isNull);
      expect(ServerOption.countryCode(''), isNull);
    });

    test('a renamed country is found by its code, the exact name wins', () {
      final renamed = [o('🇺🇸 USA', 'vless', 'ws'), o('Germany', 'vless', 'ws')];
      expect(ServerOption.resolveCountry(renamed, '🇺🇸 USA dev'), '🇺🇸 USA');
      expect(ServerOption.resolveCountry(renamed, 'Germany'), 'Germany');
      expect(ServerOption.resolveCountry([...renamed, o('🇺🇸 USA dev', 'vless', 'ws')], '🇺🇸 USA dev'), '🇺🇸 USA dev');
      expect(ServerOption.resolveCountry(renamed, 'France'), isNull);
    });

    test('resolveSelection: same or first protocol and transport; none while the country is missing', () {
      final options = [
        o('Germany', 'vless', 'tcp'),
        o('Germany', 'hysteria2', 'hy2'),
        o('France', 'vless', 'ws'),
      ];
      expect(ServerOption.resolveSelection(options, 'Germany', 'vless', 'ws')?.rawTag, 'Germany [tcp]');
      expect(ServerOption.resolveSelection(options, 'Germany', 'naive', 'naive')?.rawTag, 'Germany [tcp]');
      expect(ServerOption.resolveSelection(options, 'Germany', 'hysteria2', 'hy2')?.rawTag, 'Germany [hy2]');
      expect(ServerOption.resolveSelection(options, 'Poland', 'vless', 'ws'), isNull);
      expect(ServerOption.resolveSelection(options, ServerOption.autoCountryKey, '', ''), isNull);
      // выбор не меняется — вернулся транспорт, вернулся и сервер
      final back = [...options, o('Germany', 'vless', 'ws')];
      expect(ServerOption.resolveSelection(back, 'Germany', 'vless', 'ws')?.rawTag, 'Germany [ws]');
    });
  });
}
