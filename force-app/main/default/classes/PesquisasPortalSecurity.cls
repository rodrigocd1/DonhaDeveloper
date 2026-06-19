public class PesquisasPortalSecurity {
    public class PortalException extends Exception {
    }

    public class IdentificacaoNormalizada {
        public String cpf;
        public String email;
        public String telefone;

        public Boolean possuiIdentificador() {
            return String.isNotBlank(cpf) || String.isNotBlank(email) || String.isNotBlank(telefone);
        }
    }

    public static IdentificacaoNormalizada normalizarIdentificacao(
        PesquisasPortalDTOs.IdentificacaoInput input
    ) {
        if (input == null) {
            throw new PortalException('Informe os dados de identificação.');
        }
        IdentificacaoNormalizada resultado = new IdentificacaoNormalizada();
        resultado.cpf = normalizarDigitos(input.cpf);
        resultado.email = normalizarEmail(input.email);
        resultado.telefone = normalizarDigitos(input.telefone);
        validarIdentificacao(resultado, input);
        return resultado;
    }

    public static String textoSeguro(String valor, Integer limite) {
        if (String.isBlank(valor)) {
            return null;
        }
        String resultado = valor.stripHtmlTags().replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', '').trim();
        return resultado.length() > limite ? resultado.substring(0, limite) : resultado;
    }

    public static String nomeObrigatorio(String valor) {
        String nome = textoSeguro(valor, 120);
        if (String.isBlank(nome)) {
            throw new PortalException('Informe o nome completo.');
        }
        return nome;
    }

    public static Boolean cpfValido(String cpf) {
        if (String.isBlank(cpf) || cpf.length() != 11 || todosDigitosIguais(cpf)) {
            return false;
        }
        Integer primeiro = calcularDigitoCpf(cpf.substring(0, 9), 10);
        Integer segundo = calcularDigitoCpf(cpf.substring(0, 9) + String.valueOf(primeiro), 11);
        return cpf.endsWith(String.valueOf(primeiro) + String.valueOf(segundo));
    }

    public static String normalizarCpfObrigatorio(String cpf) {
        String normalizado = normalizarDigitos(cpf);
        if (!cpfValido(normalizado)) {
            throw new PortalException('Informe um CPF válido.');
        }
        return normalizado;
    }

    @TestVisible
    private static String normalizarDigitos(String valor) {
        return String.isBlank(valor) ? null : valor.replaceAll('\\D', '');
    }

    private static String normalizarEmail(String valor) {
        return String.isBlank(valor) ? null : valor.trim().toLowerCase();
    }

    private static void validarIdentificacao(
        IdentificacaoNormalizada normalizada,
        PesquisasPortalDTOs.IdentificacaoInput original
    ) {
        if (!normalizada.possuiIdentificador()) {
            throw new PortalException('Informe CPF, e-mail ou telefone.');
        }
        if (String.isNotBlank(original.cpf) && !cpfValido(normalizada.cpf)) {
            throw new PortalException('Informe um CPF válido.');
        }
        if (String.isNotBlank(original.email) && !emailValido(normalizada.email)) {
            throw new PortalException('Informe um e-mail válido.');
        }
        if (String.isNotBlank(original.telefone) && !telefoneValido(normalizada.telefone)) {
            throw new PortalException('Informe um telefone válido.');
        }
    }

    private static Boolean emailValido(String email) {
        return Pattern.matches('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$', email) && email.length() <= 80;
    }

    private static Boolean telefoneValido(String telefone) {
        return telefone.length() >= 8 && telefone.length() <= 15;
    }

    private static Boolean todosDigitosIguais(String cpf) {
        return Pattern.matches('^(\\d)\\1{10}$', cpf);
    }

    private static Integer calcularDigitoCpf(String base, Integer pesoInicial) {
        Integer soma = 0;
        for (Integer indice = 0; indice < base.length(); indice++) {
            soma += Integer.valueOf(base.substring(indice, indice + 1)) * (pesoInicial - indice);
        }
        Integer resto = Math.mod(soma, 11);
        return resto < 2 ? 0 : 11 - resto;
    }
}
