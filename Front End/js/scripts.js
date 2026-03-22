function doTask1() {
    const btn = document.getElementById('First');
    btn.setAttribute('disabled', '');
    btn.classList.add("button-disabled");

    const counterText = document.getElementById('FirstCounter');
    counterText.innerText++;
    const d = new Date();
    payload = JSON.stringify({
        Sender: 'First',
        Property: `Count ${counterText.innerText}`,
        EventTime: d.toISOString()
    });
    window.PowershellServer(payload);
}

function doTask2() {
    const btn = document.getElementById('Second');

    const counterText = document.getElementById('SecondCounter');
    counterText.innerText++;
    const d = new Date();
    payload = JSON.stringify({
        Sender: 'Second',
        Property: `Count ${counterText.innerText}`,
        EventTime: d.toISOString()
    });
    window.PowershellServer(payload);
}

function enableAllButtons() {
    document.getElementById("First").removeAttribute("disabled");
    document.getElementById("Second").removeAttribute("disabled");
    document.getElementById("First").classList.remove("button-disabled");
    document.getElementById("Second").classList.remove("button-disabled");
}

function enableButton(buttonId) {
    document.getElementById(buttonId).removeAttribute("disabled");
    document.getElementById(buttonId).classList.remove("button-disabled");
}

window.addEventListener('load', function () {
    const themeButton = document.getElementById('currentThemeButton');
    const dropdownContent = document.getElementById('themeDropdown');

    themeButton.addEventListener('click', function () {
        var isHidden = dropdownContent.hasAttribute('hidden');

        if (isHidden) {
            dropdownContent.removeAttribute('hidden');
        } else {
            dropdownContent.setAttribute('hidden', '');
        }
    });

    const osThemeButton = document.getElementById('osThemeButton');
    const lightThemeButton = document.getElementById('lightThemeButton');
    const darkThemeButton = document.getElementById('darkThemeButton');
    const htmlDocument = document.getElementsByTagName('html')[0]

    osThemeButton.addEventListener('click', function () {
        htmlDocument.setAttribute('data-theme', 'light dark')

        var isHidden = dropdownContent.hasAttribute('hidden');

        if (!isHidden) {
            dropdownContent.setAttribute('hidden', '');
        }
    });

    lightThemeButton.addEventListener('click', function () {
        htmlDocument.setAttribute('data-theme', 'light')

        var isHidden = dropdownContent.hasAttribute('hidden');

        if (!isHidden) {
            dropdownContent.setAttribute('hidden', '');
        }
    });

    darkThemeButton.addEventListener('click', function () {
        htmlDocument.setAttribute('data-theme', 'dark')

        var isHidden = dropdownContent.hasAttribute('hidden');

        if (!isHidden) {
            dropdownContent.setAttribute('hidden', '');
        }
    });
});
