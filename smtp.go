package main

import (
	"log"
	"net/smtp"
	"os"
	"io/ioutil"
)

func main() {
	log_name := os.Args[7]
	message_body, err := ioutil.ReadFile(log_name)
	if err != nil {
		log.Fatal(err)
		return
	}

  message := string(message_body)
	send(message)
}

func send(body string) {
	from := os.Args[1]
	pass := os.Args[2]
	to := os.Args[3]
	smtp_relay := os.Args[4]
	smtp_relay_port := os.Args[5]
	action := os.Args[6]

	msg := "From: " + from + "\n" +
		"To: " + to + "\n" +
		"Subject: " + action + " failed\n\n" +
		body

	err := smtp.SendMail(smtp_relay + ":" + smtp_relay_port,
		smtp.PlainAuth("", from, pass, smtp_relay),
		from, []string{to}, []byte(msg))

	if err != nil {
		log.Printf("smtp error: %s", err)
		return
	}

	log.Print("Mysql backup/restore operation alert has been sent")
}
