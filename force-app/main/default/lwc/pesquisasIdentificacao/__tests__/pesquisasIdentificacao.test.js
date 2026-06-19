import { createElement } from "@lwc/engine-dom";
import PesquisasIdentificacao from "c/pesquisasIdentificacao";

describe("c-pesquisas-identificacao", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("mantém somente os dados informados pelo usuário", () => {
    const element = createElement("c-pesquisas-identificacao", {
      is: PesquisasIdentificacao
    });
    document.body.appendChild(element);
    const email = element.shadowRoot.querySelector('[data-field="email"]');

    email.dispatchEvent(
      new CustomEvent("change", { detail: { value: "pessoa@exemplo.com" } })
    );

    expect(element.getValue()).toEqual({
      cpf: "",
      email: "pessoa@exemplo.com",
      telefone: ""
    });
  });

  it("rejeita o formulário sem nenhum identificador", () => {
    const element = createElement("c-pesquisas-identificacao", {
      is: PesquisasIdentificacao
    });
    document.body.appendChild(element);
    const inputs = element.shadowRoot.querySelectorAll("lightning-input");
    inputs.forEach((input) => {
      input.reportValidity = jest.fn(() => true);
    });
    inputs[0].setCustomValidity = jest.fn();

    expect(element.reportValidity()).toBe(false);
    expect(inputs[0].setCustomValidity).toHaveBeenCalledWith(
      "Informe CPF, e-mail ou telefone."
    );
  });
});
