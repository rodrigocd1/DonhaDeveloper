public with sharing class CommunicatorExternalApiDateTimeService {

    public static String formatForUser(Datetime value, String timezoneSidKey) {
        if (value == null) return null;
        String tz = String.isBlank(timezoneSidKey) ? 'America/Sao_Paulo' : timezoneSidKey;
        return value.format('yyyy-MM-dd\'T\'HH:mm:ssXXX', tz);
    }

    public static Datetime parseIsoDatetime(String rawValue) {
        if (String.isBlank(rawValue)) return null;
        try {
            return Datetime.valueOfGmt(rawValue.replace('T', ' ').replace('Z', ''));
        } catch (Exception ex) {
            try {
                return (Datetime) JSON.deserialize('"' + rawValue + '"', Datetime.class);
            } catch (Exception innerEx) {
                throw CommunicatorExternalApiErrorService.badRequest(
                    'INVALID_DATETIME',
                    'Data/hora invalida: ' + rawValue
                );
            }
        }
    }
}