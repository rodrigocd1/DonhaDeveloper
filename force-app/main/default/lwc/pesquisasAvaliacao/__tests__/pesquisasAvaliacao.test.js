import { createElement } from "@lwc/engine-dom";
import PesquisasAvaliacao from "c/pesquisasAvaliacao";
import registrarAvaliacao from "@salesforce/apex/PesquisasPortalController.registrarAvaliacao";

jest.mock(
  "@salesforce/apex/PesquisasPortalController.registrarAvaliacao",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () => Promise.resolve();

describe("c-pesquisas-avaliacao", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("exige uma nota antes de submeter", async () => {
    const element = createElement("c-pesquisas-avaliacao", {
      is: PesquisasAvaliacao
    });
    document.body.appendChild(element);
    element.shadowRoot
      .querySelectorAll("lightning-input, lightning-textarea")
      .forEach((field) => {
        field.reportValidity = jest.fn(() => true);
      });

    element.shadowRoot
      .querySelector("form")
      .dispatchEvent(new CustomEvent("submit"));
    await flushPromises();

    expect(registrarAvaliacao).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("1 a 5");
  });

  it("envia uma única avaliação durante submissões repetidas", async () => {
    let resolveRequest;
    registrarAvaliacao.mockReturnValue(
      new Promise((resolve) => {
        resolveRequest = resolve;
      })
    );
    const element = createElement("c-pesquisas-avaliacao", {
      is: PesquisasAvaliacao
    });
    document.body.appendChild(element);
    const inputs = element.shadowRoot.querySelectorAll("lightning-input");
    inputs.forEach((field) => {
      field.reportValidity = jest.fn(() => true);
      field.dispatchEvent(
        new CustomEvent("change", { detail: { value: "Valor preenchido" } })
      );
    });
    element.shadowRoot.querySelector("lightning-textarea").reportValidity =
      jest.fn(() => true);
    element.shadowRoot.querySelector('[data-rating="5"]').click();
    const form = element.shadowRoot.querySelector("form");

    form.dispatchEvent(new CustomEvent("submit"));
    form.dispatchEvent(new CustomEvent("submit"));
    expect(registrarAvaliacao).toHaveBeenCalledTimes(1);
    expect(registrarAvaliacao.mock.calls[0][0].input.nota).toBe(5);

    resolveRequest({ mensagem: "Avaliação registrada." });
    await flushPromises();
  });
});
